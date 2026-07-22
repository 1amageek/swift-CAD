import Foundation
import CADCore

public struct CertifiedImplicitIntersectionGraphCell: Sendable, Hashable {
    public let parameterBox: SurfaceIntersectionParameterBox
    public let freeParameter: SurfaceIntersectionParameterCoordinate
    public let direction: CertifiedImplicitIntersectionDirection
    public let lowerAnchor: SurfaceIntersectionParameterPair
    public let midpointAnchor: SurfaceIntersectionParameterPair
    public let upperAnchor: SurfaceIntersectionParameterPair

    public init(
        parameterBox: SurfaceIntersectionParameterBox,
        freeParameter: SurfaceIntersectionParameterCoordinate,
        direction: CertifiedImplicitIntersectionDirection,
        lowerAnchor: SurfaceIntersectionParameterPair,
        midpointAnchor: SurfaceIntersectionParameterPair,
        upperAnchor: SurfaceIntersectionParameterPair,
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        self.parameterBox = parameterBox
        self.freeParameter = freeParameter
        self.direction = direction
        self.lowerAnchor = lowerAnchor
        self.midpointAnchor = midpointAnchor
        self.upperAnchor = upperAnchor
        try validate(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    public func validate(
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try firstSurface.validate(tolerance: tolerance)
        try secondSurface.validate(tolerance: tolerance)
        try parameterBox.validate(
            first: firstSurface,
            second: secondSurface,
            tolerance: tolerance
        )
        guard parameterBox.contains(lowerAnchor),
              parameterBox.contains(midpointAnchor),
              parameterBox.contains(upperAnchor) else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "An implicit intersection graph anchor lies outside its certified parameter box."
            )
        }
        let freeInterval = parameterBox.interval(for: freeParameter)
        let freeIndex = freeParameter.rawValue
        let freeValues = [
            lowerAnchor.values[freeIndex],
            midpointAnchor.values[freeIndex],
            upperAnchor.values[freeIndex],
        ]
        let expectedValues = [freeInterval.lower, freeInterval.midpoint, freeInterval.upper]
        guard zip(freeValues, expectedValues).allSatisfy({ value, expected in
            abs(value - expected) <= tolerance.relative
        }) else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "Implicit intersection graph anchors do not span the certified free-parameter interval."
            )
        }
        for anchor in [lowerAnchor, midpointAnchor, upperAnchor] {
            _ = try verifiedPoint(
                parameters: anchor,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
        }
        try validateGraphProof(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    public func parameterPair(
        atNormalizedFraction fraction: Double,
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntersectionParameterPair {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        let directedFraction = direction == .forward
            ? clampedFraction
            : 1.0 - clampedFraction
        let freeInterval = parameterBox.interval(for: freeParameter)
        let freeValue = freeInterval.lower + freeInterval.width * directedFraction
        var values = initialValues(atNormalizedFraction: directedFraction)
        values[freeParameter.rawValue] = freeValue
        let dependentIndexes = SurfaceIntersectionParameterCoordinate.allCases
            .map(\.rawValue)
            .filter { $0 != freeParameter.rawValue }
        var previousResidual = Double.infinity
        for _ in 0..<32 {
            let currentSample = try sample(
                values: values,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                tolerance: tolerance
            )
            if currentSample.residual <= tolerance.distance {
                return try SurfaceIntersectionParameterPair(values: values)
            }
            let dependentColumns = dependentIndexes.map { currentSample.columns[$0] }
            guard let delta = Self.solve(
                columns: dependentColumns,
                rightHandSide: currentSample.difference * -1.0
            ) else {
                throw certificateFailure(
                    tolerance: tolerance,
                    residual: currentSample.residual,
                    message: "A certified implicit intersection graph produced a singular numerical refinement system."
                )
            }
            var acceptedValues: [Double]?
            var scale = 1.0
            for _ in 0..<12 {
                var candidate = values
                for index in dependentIndexes.indices {
                    let parameterIndex = dependentIndexes[index]
                    let interval = parameterBox.intervals[parameterIndex]
                    candidate[parameterIndex] = min(
                        max(values[parameterIndex] + delta[index] * scale, interval.lower),
                        interval.upper
                    )
                }
                candidate[freeParameter.rawValue] = freeValue
                let candidateSample = try self.sample(
                    values: candidate,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    tolerance: tolerance
                )
                if candidateSample.residual < currentSample.residual {
                    acceptedValues = candidate
                    previousResidual = candidateSample.residual
                    break
                }
                scale *= 0.5
            }
            guard let acceptedValues else {
                throw certificateFailure(
                    tolerance: tolerance,
                    residual: currentSample.residual,
                    message: "A certified implicit intersection graph root could not be numerically refined."
                )
            }
            values = acceptedValues
            if previousResidual <= tolerance.distance {
                return try SurfaceIntersectionParameterPair(values: values)
            }
        }
        let finalSample = try sample(
            values: values,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        guard finalSample.residual <= tolerance.distance else {
            throw certificateFailure(
                tolerance: tolerance,
                residual: finalSample.residual,
                message: "A certified implicit intersection graph exceeded its root-refinement iteration limit."
            )
        }
        return try SurfaceIntersectionParameterPair(values: values)
    }

    public func point(
        atNormalizedFraction fraction: Double,
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        let parameters = try parameterPair(
            atNormalizedFraction: fraction,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        return try verifiedPoint(
            parameters: parameters,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        parameterScale: Double,
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionDifferential {
        guard parameterScale.isFinite, parameterScale > 0.0 else {
            throw GeometryError.invalidDistance(parameterScale)
        }
        let parameters = try parameterPair(
            atNormalizedFraction: fraction,
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let values = parameters.values
        let firstGeometry = try firstSurface.differentialGeometry(
            atU: values[0],
            v: values[1],
            tolerance: tolerance
        )
        let secondGeometry = try secondSurface.differentialGeometry(
            atU: values[2],
            v: values[3],
            tolerance: tolerance
        )
        let columns = [
            firstGeometry.tangentU,
            firstGeometry.tangentV,
            secondGeometry.tangentU * -1.0,
            secondGeometry.tangentV * -1.0,
        ]
        let freeIndex = freeParameter.rawValue
        let dependentIndexes = SurfaceIntersectionParameterCoordinate.allCases
            .map(\.rawValue)
            .filter { $0 != freeIndex }
        var firstParameterDerivatives = Array(repeating: 0.0, count: 4)
        firstParameterDerivatives[freeIndex] = parameterBox
            .interval(for: freeParameter).width
            * parameterScale
            * (direction == .forward ? 1.0 : -1.0)
        let firstRightHandSide = columns[freeIndex]
            * -firstParameterDerivatives[freeIndex]
        guard let dependentFirstDerivatives = Self.solve(
            columns: dependentIndexes.map { columns[$0] },
            rightHandSide: firstRightHandSide
        ) else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "A certified implicit intersection graph has no regular first differential."
            )
        }
        for index in dependentIndexes.indices {
            firstParameterDerivatives[dependentIndexes[index]] = dependentFirstDerivatives[index]
        }

        let firstSurfaceQuadratic = firstGeometry.secondDerivativeUU
                * (firstParameterDerivatives[0] * firstParameterDerivatives[0])
            + firstGeometry.secondDerivativeUV
                * (2.0 * firstParameterDerivatives[0] * firstParameterDerivatives[1])
            + firstGeometry.secondDerivativeVV
                * (firstParameterDerivatives[1] * firstParameterDerivatives[1])
        let secondSurfaceQuadratic = secondGeometry.secondDerivativeUU
                * (firstParameterDerivatives[2] * firstParameterDerivatives[2])
            + secondGeometry.secondDerivativeUV
                * (2.0 * firstParameterDerivatives[2] * firstParameterDerivatives[3])
            + secondGeometry.secondDerivativeVV
                * (firstParameterDerivatives[3] * firstParameterDerivatives[3])
        let secondRightHandSide = (firstSurfaceQuadratic - secondSurfaceQuadratic) * -1.0
        guard let dependentSecondDerivatives = Self.solve(
            columns: dependentIndexes.map { columns[$0] },
            rightHandSide: secondRightHandSide
        ) else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "A certified implicit intersection graph has no regular second differential."
            )
        }
        var secondParameterDerivatives = Array(repeating: 0.0, count: 4)
        for index in dependentIndexes.indices {
            secondParameterDerivatives[dependentIndexes[index]] = dependentSecondDerivatives[index]
        }

        let firstPoint = firstGeometry.position
        let secondPoint = secondGeometry.position
        let residual = (firstPoint - secondPoint).length
        guard residual <= tolerance.distance else {
            throw certificateFailure(
                tolerance: tolerance,
                residual: residual,
                message: "A certified implicit intersection differential failed dual-surface residual verification."
            )
        }
        let firstSpatialDerivative = firstGeometry.tangentU * firstParameterDerivatives[0]
            + firstGeometry.tangentV * firstParameterDerivatives[1]
        let secondSpatialFirstDerivative = secondGeometry.tangentU * firstParameterDerivatives[2]
            + secondGeometry.tangentV * firstParameterDerivatives[3]
        let firstDerivativeResidual = (firstSpatialDerivative - secondSpatialFirstDerivative).length
        let firstDerivativeScale = max(
            max(firstSpatialDerivative.length, secondSpatialFirstDerivative.length),
            Double.leastNonzeroMagnitude
        )
        guard firstDerivativeResidual <= tolerance.relative * firstDerivativeScale else {
            throw certificateFailure(
                tolerance: tolerance,
                residual: firstDerivativeResidual / firstDerivativeScale,
                message: "A certified implicit intersection differential has inconsistent dual-surface tangents."
            )
        }
        let secondSpatialDerivative = firstGeometry.tangentU * secondParameterDerivatives[0]
            + firstGeometry.tangentV * secondParameterDerivatives[1]
            + firstSurfaceQuadratic
        let secondSpatialSecondDerivative = secondGeometry.tangentU * secondParameterDerivatives[2]
            + secondGeometry.tangentV * secondParameterDerivatives[3]
            + secondSurfaceQuadratic
        let secondDerivativeResidual = (secondSpatialDerivative - secondSpatialSecondDerivative).length
        let secondDerivativeScale = max(
            max(secondSpatialDerivative.length, secondSpatialSecondDerivative.length),
            1.0
        )
        guard secondDerivativeResidual <= tolerance.relative * secondDerivativeScale else {
            throw certificateFailure(
                tolerance: tolerance,
                residual: secondDerivativeResidual / secondDerivativeScale,
                message: "A certified implicit intersection differential has inconsistent dual-surface curvature."
            )
        }
        return CertifiedImplicitIntersectionDifferential(
            position: Point3D(
                x: (firstPoint.x + secondPoint.x) * 0.5,
                y: (firstPoint.y + secondPoint.y) * 0.5,
                z: (firstPoint.z + secondPoint.z) * 0.5
            ),
            firstDerivative: (firstSpatialDerivative + secondSpatialFirstDerivative) * 0.5,
            secondDerivative: (secondSpatialDerivative + secondSpatialSecondDerivative) * 0.5,
            parameters: parameters,
            firstParameterDerivatives: try SurfaceIntersectionParameterVector(
                values: firstParameterDerivatives
            ),
            secondParameterDerivatives: try SurfaceIntersectionParameterVector(
                values: secondParameterDerivatives
            )
        )
    }

    package func parameterDerivativeBounds(
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> [ScalarInterval] {
        try tolerance.validate()
        let difference = try differencePatch(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        guard let normalizedBounds = try difference
            .normalizedGraphParameterDerivativeBounds(
                freeParameterIndex: freeParameter.rawValue
            ) else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "An implicit intersection graph has no finite interval parameter derivative enclosure."
            )
        }
        let traversalSign = direction == .forward ? 1.0 : -1.0
        return try zip(normalizedBounds, parameterBox.intervals).map {
            normalized, parameterInterval in
            let scale = parameterInterval.width * traversalSign
            let products = [normalized.lower * scale, normalized.upper * scale]
            guard let lower = products.min(),
                  let upper = products.max(),
                  lower.isFinite,
                  upper.isFinite else {
                throw certificateFailure(
                    tolerance: tolerance,
                    message: "An implicit intersection parameter derivative exceeded finite interval arithmetic."
                )
            }
            return try ScalarInterval(
                lower: lower.nextDown,
                upper: upper.nextUp
            )
        }
    }

    private func validateGraphProof(
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        let difference = try differencePatch(
            firstSurface: firstSurface,
            secondSurface: secondSurface,
            tolerance: tolerance
        )
        let intervals = parameterBox.intervals
        let normalizedLowerAnchor = zip(lowerAnchor.values, intervals).map {
            value, interval in
            (value - interval.lower) / interval.width
        }
        let normalizedUpperAnchor = zip(upperAnchor.values, intervals).map {
            value, interval in
            (value - interval.lower) / interval.width
        }
        let reproducedCertificate = difference.affinePredictorGaugeRootCertificate(
            freeParameterIndex: freeParameter.rawValue,
            lowerAnchor: normalizedLowerAnchor,
            upperAnchor: normalizedUpperAnchor
        )
        if reproducedCertificate
            == .fullGraph(freeParameterIndex: freeParameter.rawValue) {
            return
        }
        if let exactGraph = try ExactAffineBilinearIntersectionGraph.certified(
            first: firstSurface,
            second: secondSurface,
            tolerance: tolerance
        ), try exactGraph.certifies(
            parameterBox: parameterBox,
            freeParameter: freeParameter,
            lowerAnchor: lowerAnchor,
            midpointAnchor: midpointAnchor,
            upperAnchor: upperAnchor,
            first: firstSurface,
            second: secondSurface,
            tolerance: tolerance
        ) {
            return
        }
        let predictorDiagnostic = difference.affinePredictorProofDiagnostic(
            freeParameterIndex: freeParameter.rawValue,
            lowerAnchor: normalizedLowerAnchor,
            upperAnchor: normalizedUpperAnchor
        )
        throw certificateFailure(
            tolerance: tolerance,
            message: "The stored implicit intersection cell reproduced \(reproducedCertificate) instead of a full-graph Krawczyk or exact affine-bilinear proof. Parameter widths: \(parameterBox.intervals.map(\.width)). Predictor: \(predictorDiagnostic)."
        )
    }

    private func differencePatch(
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> RationalBezierSurfaceSurfaceDifferencePatch {
        let trimmedFirst = try firstSurface.trimmed(
            uFrom: parameterBox.firstU.lower,
            uTo: parameterBox.firstU.upper,
            vFrom: parameterBox.firstV.lower,
            vTo: parameterBox.firstV.upper,
            tolerance: tolerance
        )
        let trimmedSecond = try secondSurface.trimmed(
            uFrom: parameterBox.secondU.lower,
            uTo: parameterBox.secondU.upper,
            vFrom: parameterBox.secondV.lower,
            vTo: parameterBox.secondV.upper,
            tolerance: tolerance
        )
        let decomposer = BSplineSurfaceBezierDecomposer()
        let firstPatches = try decomposer.surfacePatches(
            surface: trimmedFirst,
            tolerance: tolerance
        )
        let secondPatches = try decomposer.surfacePatches(
            surface: trimmedSecond,
            tolerance: tolerance
        )
        guard firstPatches.count == 1,
              secondPatches.count == 1 else {
            throw certificateFailure(
                tolerance: tolerance,
                message: "An implicit intersection graph cell must remain inside one Bezier span on each surface."
            )
        }
        return try RationalBezierSurfaceSurfaceDifferencePatch(
            first: firstPatches[0],
            second: secondPatches[0],
            tolerance: tolerance
        )
    }

    public var startAnchor: SurfaceIntersectionParameterPair {
        direction == .forward ? lowerAnchor : upperAnchor
    }

    public var endAnchor: SurfaceIntersectionParameterPair {
        direction == .forward ? upperAnchor : lowerAnchor
    }

    private func verifiedPoint(
        parameters: SurfaceIntersectionParameterPair,
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        let firstPoint = try firstSurface.point(
            u: parameters.first.u,
            v: parameters.first.v,
            tolerance: tolerance
        )
        let secondPoint = try secondSurface.point(
            u: parameters.second.u,
            v: parameters.second.v,
            tolerance: tolerance
        )
        let residual = (firstPoint - secondPoint).length
        guard residual <= tolerance.distance else {
            throw certificateFailure(
                tolerance: tolerance,
                residual: residual,
                message: "An implicit intersection graph point failed dual-surface residual verification."
            )
        }
        return Point3D(
            x: (firstPoint.x + secondPoint.x) * 0.5,
            y: (firstPoint.y + secondPoint.y) * 0.5,
            z: (firstPoint.z + secondPoint.z) * 0.5
        )
    }

    private func initialValues(atNormalizedFraction fraction: Double) -> [Double] {
        if fraction <= 0.5 {
            return Self.interpolate(
                lowerAnchor.values,
                midpointAnchor.values,
                fraction: fraction * 2.0
            )
        }
        return Self.interpolate(
            midpointAnchor.values,
            upperAnchor.values,
            fraction: (fraction - 0.5) * 2.0
        )
    }

    private func sample(
        values: [Double],
        firstSurface: BSplineSurface3D,
        secondSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> (difference: Vector3D, residual: Double, columns: [Vector3D]) {
        let firstGeometry = try firstSurface.differentialGeometry(
            atU: values[0],
            v: values[1],
            tolerance: tolerance
        )
        let secondGeometry = try secondSurface.differentialGeometry(
            atU: values[2],
            v: values[3],
            tolerance: tolerance
        )
        let difference = firstGeometry.position - secondGeometry.position
        return (
            difference,
            difference.length,
            [
                firstGeometry.tangentU,
                firstGeometry.tangentV,
                secondGeometry.tangentU * -1.0,
                secondGeometry.tangentV * -1.0,
            ]
        )
    }

    private static func solve(
        columns: [Vector3D],
        rightHandSide: Vector3D
    ) -> [Double]? {
        guard columns.count == 3 else { return nil }
        let cross = columns[1].cross(columns[2])
        let determinant = columns[0].dot(cross)
        let scale = columns.map(\.length).max() ?? .infinity
        let floor = max(
            scale * scale * scale * Double.ulpOfOne * 1_024.0,
            Double.leastNonzeroMagnitude
        )
        guard determinant.isFinite,
              scale.isFinite,
              abs(determinant) > floor else {
            return nil
        }
        return [
            rightHandSide.dot(cross) / determinant,
            columns[0].dot(rightHandSide.cross(columns[2])) / determinant,
            columns[0].dot(columns[1].cross(rightHandSide)) / determinant,
        ]
    }

    private static func interpolate(
        _ lower: [Double],
        _ upper: [Double],
        fraction: Double
    ) -> [Double] {
        zip(lower, upper).map { lowerValue, upperValue in
            lowerValue + (upperValue - lowerValue) * fraction
        }
    }

    private func certificateFailure(
        tolerance: ModelingTolerance,
        residual: Double? = nil,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }
}

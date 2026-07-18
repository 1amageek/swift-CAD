import Foundation
import CADCore

struct AnalyticBSplineSurfaceIntersector {
    private struct RemapSample {
        let point: Point3D
        let analyticParameter: Point2D
        let boundedParameter: Point2D
    }

    func intersections(
        analytic: CanonicalAnalyticSurface,
        surface: BSplineSurface3D,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        analyticIsFirst: Bool,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceSurfaceIntersection] {
        try options.validate(tolerance: tolerance)
        let seamOffsets = try periodicSeamOffsets(
            analytic: analytic,
            reference: surface,
            count: options.maximumPeriodicSeamAttempts,
            tolerance: tolerance
        )
        var lastRetryableError: KernelError?
        for periodicSeamOffset in seamOffsets {
            let analyticBSpline = try AnalyticSurfaceBSplineBuilder().surface(
                for: analytic,
                boundedBy: surface,
                periodicSeamOffset: periodicSeamOffset,
                tolerance: tolerance
            )
            let internalFirst = analyticIsFirst ? analyticBSpline : surface
            let internalSecond = analyticIsFirst ? surface : analyticBSpline
            let raw: [SurfaceSurfaceIntersection]
            do {
                raw = try BoundedBSplineSurfaceIntersector().intersections(
                    first: internalFirst,
                    second: internalSecond,
                    firstSurface: .bSpline(internalFirst),
                    secondSurface: .bSpline(internalSecond),
                    options: options,
                    tolerance: tolerance
                )
            } catch let error as KernelError
                where error.code == .resourceLimitExceeded
                    || error.code == .intersectionFailure {
                lastRetryableError = error
                continue
            }
            guard try containsPeriodicPatchBoundaryCoincidence(
                raw,
                analytic: analytic,
                analyticBSpline: analyticBSpline,
                analyticIsFirst: analyticIsFirst,
                tolerance: tolerance
            ) == false else {
                continue
            }
            return try raw.map {
                try remapped(
                    $0,
                    firstSurface: firstSurface,
                    secondSurface: secondSurface,
                    boundedSurface: surface,
                    analyticIsFirst: analyticIsFirst,
                    tolerance: tolerance
                )
            }
        }
        if let lastRetryableError {
            throw lastRetryableError
        }
        throw KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: "Analytic–B-spline intersection exhausted the periodic seam retry limit."
        )
    }

    private func periodicSeamOffsets(
        analytic: CanonicalAnalyticSurface,
        reference: BSplineSurface3D,
        count: Int,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let initialOffset = Double.pi * 0.125
        let goldenAngle = Double.pi * (3.0 - sqrt(5.0))
        let candidates = (0..<count).map {
            initialOffset + Double($0) * goldenAngle
        }
        let occupiedAngles = try periodicReferenceAngles(
            analytic: analytic,
            reference: reference,
            tolerance: tolerance
        )
        guard occupiedAngles.isEmpty == false else { return candidates }
        return candidates.enumerated().sorted { first, second in
            let firstClearance = minimumPeriodicPatchBoundaryClearance(
                first.element,
                occupiedAngles: occupiedAngles
            )
            let secondClearance = minimumPeriodicPatchBoundaryClearance(
                second.element,
                occupiedAngles: occupiedAngles
            )
            if abs(firstClearance - secondClearance) > tolerance.angle {
                return firstClearance > secondClearance
            }
            return first.offset < second.offset
        }.map(\.element)
    }

    private func periodicReferenceAngles(
        analytic: CanonicalAnalyticSurface,
        reference: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> [Double] {
        let origin: Point3D
        let axis: Vector3D
        let torusMajorRadius: Double?
        switch analytic {
        case let .cylinder(cylinder):
            origin = cylinder.origin
            axis = cylinder.axis
            torusMajorRadius = nil
        case let .cone(cone):
            origin = cone.apex
            axis = cone.axis
            torusMajorRadius = nil
        case let .sphere(sphere):
            origin = sphere.center
            axis = .unitZ
            torusMajorRadius = nil
        case let .torus(torus):
            origin = torus.center
            axis = torus.axis
            torusMajorRadius = torus.majorRadius
        case .plane, .unsupported:
            return []
        }
        let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
        var result: [Double] = []
        result.reserveCapacity(reference.controlPoints.count * reference.controlPoints[0].count * 2)
        for point in reference.controlPoints.flatMap({ $0 }) {
            let displacement = point - origin
            let axial = displacement.dot(axis)
            let radial = displacement - axis * axial
            let radialLength = radial.length
            guard radialLength > tolerance.distance else { continue }
            result.append(atan2(radial.dot(basis.v), radial.dot(basis.u)))
            if let torusMajorRadius {
                result.append(atan2(axial, radialLength - torusMajorRadius))
            }
        }
        return result
    }

    private func minimumPeriodicPatchBoundaryClearance(
        _ candidate: Double,
        occupiedAngles: [Double]
    ) -> Double {
        (0..<4).flatMap { quadrant in
            let boundary = candidate + Double(quadrant) * Double.pi * 0.5
            return occupiedAngles.map { occupied in
                let difference = abs(boundary - occupied)
                    .truncatingRemainder(dividingBy: 2.0 * Double.pi)
                return min(difference, 2.0 * Double.pi - difference)
            }
        }.min() ?? Double.pi
    }

    private func containsPeriodicPatchBoundaryCoincidence(
        _ intersections: [SurfaceSurfaceIntersection],
        analytic: CanonicalAnalyticSurface,
        analyticBSpline: BSplineSurface3D,
        analyticIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let directions: [SurfaceParameterDirection]
        switch analytic {
        case .cylinder, .cone, .sphere:
            directions = [.u]
        case .torus:
            directions = [.u, .v]
        case .plane, .unsupported:
            directions = []
        }
        for intersection in intersections {
            guard case let .curve(curve) = intersection else { continue }
            let pcurve = analyticIsFirst
                ? curve.firstSurfaceParameterCurve
                : curve.secondSurfaceParameterCurve
            for direction in directions where try liesOnPeriodicPatchBoundary(
                pcurve,
                direction: direction,
                surface: analyticBSpline,
                tolerance: tolerance
            ) {
                return true
            }
        }
        return false
    }

    private func liesOnPeriodicPatchBoundary(
        _ pcurve: SurfaceParameterCurve,
        direction: SurfaceParameterDirection,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        let domain = direction == .u ? surface.uDomain : surface.vDomain
        let knots = direction == .u ? surface.uKnots : surface.vKnots
        guard case let .closed(lower, upper) = domain else { return false }
        let parameterTolerance = max(
            tolerance.angle * 4.0 / Double.pi,
            tolerance.distance * 8.0,
            Double.ulpOfOne * 256.0
        )
        let values = try (0...8).map { index in
            let parameter = try pcurve.parameter(
                atNormalizedFraction: Double(index) / 8.0,
                tolerance: tolerance
            )
            return direction == .u ? parameter.u : parameter.v
        }
        if values.allSatisfy({
            min(abs($0 - lower), abs($0 - upper)) <= parameterTolerance
        }) {
            return true
        }
        let internalBoundaries = Array(Set(knots)).filter {
            $0 > lower + parameterTolerance && $0 < upper - parameterTolerance
        }
        for boundary in internalBoundaries {
            if values.allSatisfy({ abs($0 - boundary) <= parameterTolerance }) {
                return true
            }
        }
        return false
    }

    private func remapped(
        _ intersection: SurfaceSurfaceIntersection,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        boundedSurface: BSplineSurface3D,
        analyticIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        switch intersection {
        case let .curve(value):
            return try remappedCurve(
                value,
                firstSurface: firstSurface,
                secondSurface: secondSurface,
                boundedSurface: boundedSurface,
                analyticIsFirst: analyticIsFirst,
                tolerance: tolerance
            )
        case let .point(value):
            let firstProjection = try firstSurface.parameterProjection(
                of: value.point,
                tolerance: tolerance
            )
            let secondProjection = try secondSurface.parameterProjection(
                of: value.point,
                tolerance: tolerance
            )
            return .point(try SurfaceSurfaceIntersectionPoint(
                point: value.point,
                firstSurfaceParameter: firstProjection,
                secondSurfaceParameter: secondProjection,
                residual: max(firstProjection.residual, secondProjection.residual),
                tolerance: tolerance
            ))
        case let .coincident(value):
            return .coincident(value)
        }
    }

    private func remappedCurve(
        _ intersection: SurfaceSurfaceIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        boundedSurface: BSplineSurface3D,
        analyticIsFirst: Bool,
        tolerance: ModelingTolerance
    ) throws -> SurfaceSurfaceIntersection {
        guard case let .bSpline(curve) = intersection.curve,
              curve.degree == 1,
              case let .bSpline(firstPcurve) = intersection.firstSurfaceParameterCurve,
              case let .bSpline(secondPcurve) = intersection.secondSurfaceParameterCurve else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Adaptive analytic–B-spline remapping requires synchronized degree-one curves."
            )
        }
        let boundedPcurve = analyticIsFirst ? secondPcurve : firstPcurve
        guard boundedPcurve.degree == 1,
              curve.controlPoints.count == boundedPcurve.controlPoints.count,
              curve.controlPoints.count >= 2 else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "Adaptive analytic–B-spline remapping received inconsistent curve samples."
            )
        }
        let analyticSurface = analyticIsFirst ? firstSurface : secondSurface
        var source: [RemapSample] = []
        source.reserveCapacity(curve.controlPoints.count)
        for index in curve.controlPoints.indices {
            let point = curve.controlPoints[index]
            let projection = try analyticSurface.parameterProjection(
                of: point,
                tolerance: tolerance
            )
            let projected = Point2D(x: projection.u, y: projection.v)
            let reference = source.last?.analyticParameter ?? projected
            source.append(RemapSample(
                point: point,
                analyticParameter: unwrapped(
                    projected,
                    near: reference,
                    surface: analyticSurface
                ),
                boundedParameter: boundedPcurve.controlPoints[index]
            ))
        }

        var samples = [source[0]]
        var remainingPointCount = 65_536
        for index in 1..<source.count {
            try refineRemapping(
                first: source[index - 1],
                second: source[index],
                depth: 0,
                analyticSurface: analyticSurface,
                boundedSurface: boundedSurface,
                tolerance: tolerance,
                remainingPointCount: &remainingPointCount,
                result: &samples
            )
        }
        let knots = degreeOneKnots(controlPointCount: samples.count)
        let remappedCurve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: knots,
            controlPoints: samples.map(\.point)
        ))
        let analyticPcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: knots,
            controlPoints: samples.map(\.analyticParameter)
        ))
        let remappedBoundedPcurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: knots,
            controlPoints: samples.map(\.boundedParameter)
        ))
        try analyticPcurve.validate(on: analyticSurface, tolerance: tolerance)
        try remappedBoundedPcurve.validate(
            on: .bSpline(boundedSurface),
            tolerance: tolerance
        )
        let maximumResidual = try verifiedResidual(
            samples: samples,
            analyticSurface: analyticSurface,
            boundedSurface: boundedSurface,
            tolerance: tolerance
        )
        let firstAnchor = try firstSurface.parameterProjection(
            of: samples[0].point,
            tolerance: tolerance
        )
        let secondAnchor = try secondSurface.parameterProjection(
            of: samples[0].point,
            tolerance: tolerance
        )
        return .curve(try SurfaceSurfaceIntersectionCurve(
            curve: remappedCurve,
            kind: intersection.kind,
            firstSurfaceParameterCurve: analyticIsFirst
                ? analyticPcurve
                : remappedBoundedPcurve,
            secondSurfaceParameterCurve: analyticIsFirst
                ? remappedBoundedPcurve
                : analyticPcurve,
            firstSurfaceAnchor: firstAnchor,
            secondSurfaceAnchor: secondAnchor,
            maximumResidual: maximumResidual,
            tolerance: tolerance
        ))
    }

    private func refineRemapping(
        first: RemapSample,
        second: RemapSample,
        depth: Int,
        analyticSurface: Surface3D,
        boundedSurface: BSplineSurface3D,
        tolerance: ModelingTolerance,
        remainingPointCount: inout Int,
        result: inout [RemapSample]
    ) throws {
        let residual = try segmentResidual(
            first: first,
            second: second,
            analyticSurface: analyticSurface,
            boundedSurface: boundedSurface,
            tolerance: tolerance
        )
        if residual <= tolerance.distance * 0.5 {
            result.append(second)
            return
        }
        guard depth < 18, remainingPointCount > 0 else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: residual,
                tolerance: tolerance,
                message: "Adaptive analytic pcurve remapping exceeded its refinement limit."
            )
        }
        remainingPointCount -= 1
        let point = interpolated(first.point, second.point, fraction: 0.5)
        let expected = interpolated(
            first.analyticParameter,
            second.analyticParameter,
            fraction: 0.5
        )
        let projection = try analyticSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        let middle = RemapSample(
            point: point,
            analyticParameter: unwrapped(
                Point2D(x: projection.u, y: projection.v),
                near: expected,
                surface: analyticSurface
            ),
            boundedParameter: interpolated(
                first.boundedParameter,
                second.boundedParameter,
                fraction: 0.5
            )
        )
        try refineRemapping(
            first: first,
            second: middle,
            depth: depth + 1,
            analyticSurface: analyticSurface,
            boundedSurface: boundedSurface,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount,
            result: &result
        )
        try refineRemapping(
            first: middle,
            second: second,
            depth: depth + 1,
            analyticSurface: analyticSurface,
            boundedSurface: boundedSurface,
            tolerance: tolerance,
            remainingPointCount: &remainingPointCount,
            result: &result
        )
    }

    private func segmentResidual(
        first: RemapSample,
        second: RemapSample,
        analyticSurface: Surface3D,
        boundedSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var maximum = 0.0
        for fraction in [0.25, 0.5, 0.75] {
            let point = interpolated(first.point, second.point, fraction: fraction)
            let analyticUV = interpolated(
                first.analyticParameter,
                second.analyticParameter,
                fraction: fraction
            )
            let boundedUV = interpolated(
                first.boundedParameter,
                second.boundedParameter,
                fraction: fraction
            )
            let analyticPoint = try analyticSurface.point(
                u: analyticUV.x,
                v: analyticUV.y,
                tolerance: tolerance
            )
            let boundedPoint = try boundedSurface.point(
                u: boundedUV.x,
                v: boundedUV.y,
                tolerance: tolerance
            )
            maximum = max(
                maximum,
                (point - analyticPoint).length,
                (point - boundedPoint).length
            )
        }
        return maximum
    }

    private func verifiedResidual(
        samples: [RemapSample],
        analyticSurface: Surface3D,
        boundedSurface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> Double {
        var maximum = 0.0
        for index in 1..<samples.count {
            maximum = max(
                maximum,
                try segmentResidual(
                    first: samples[index - 1],
                    second: samples[index],
                    analyticSurface: analyticSurface,
                    boundedSurface: boundedSurface,
                    tolerance: tolerance
                )
            )
        }
        guard maximum <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximum,
                tolerance: tolerance,
                message: "Analytic–B-spline intersection failed adaptive residual verification."
            )
        }
        return maximum
    }

    private func unwrapped(
        _ value: Point2D,
        near reference: Point2D,
        surface: Surface3D
    ) -> Point2D {
        Point2D(
            x: unwrapped(value.x, near: reference.x, domain: surface.uDomain),
            y: unwrapped(value.y, near: reference.y, domain: surface.vDomain)
        )
    }

    private func unwrapped(
        _ value: Double,
        near reference: Double,
        domain: ParameterDomain
    ) -> Double {
        guard case let .periodic(period) = domain else { return value }
        return value + ((reference - value) / period).rounded() * period
    }

    private func degreeOneKnots(controlPointCount: Int) -> [Double] {
        [0.0, 0.0]
            + (1..<(controlPointCount - 1)).map(Double.init)
            + [Double(controlPointCount - 1), Double(controlPointCount - 1)]
    }

    private func interpolated(
        _ first: Point2D,
        _ second: Point2D,
        fraction: Double
    ) -> Point2D {
        Point2D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction
        )
    }

    private func interpolated(
        _ first: Point3D,
        _ second: Point3D,
        fraction: Double
    ) -> Point3D {
        Point3D(
            x: first.x + (second.x - first.x) * fraction,
            y: first.y + (second.y - first.y) * fraction,
            z: first.z + (second.z - first.z) * fraction
        )
    }
}

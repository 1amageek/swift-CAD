import CADCore

package struct ImplicitCurveIntervalJetEncloser: Sendable {
    private struct PreparedSurfaces: Sendable {
        let first: PreparedBSplineSurfaceDifferentialEncloser
        let second: PreparedBSplineSurfaceDifferentialEncloser
        let parameterDerivativeBounds: [[ScalarInterval]]
        let exactIsoparametricGraph: ExactIsoparametricPlanarIntersectionGraph?
    }

    private struct IntervalVector: Sendable {
        let x: OutwardScalarInterval
        let y: OutwardScalarInterval
        let z: OutwardScalarInterval

        static let zero = IntervalVector(
            x: OutwardScalarInterval(0.0),
            y: OutwardScalarInterval(0.0),
            z: OutwardScalarInterval(0.0)
        )

        static func + (lhs: IntervalVector, rhs: IntervalVector) -> IntervalVector {
            IntervalVector(
                x: lhs.x + rhs.x,
                y: lhs.y + rhs.y,
                z: lhs.z + rhs.z
            )
        }

        static func - (lhs: IntervalVector, rhs: IntervalVector) -> IntervalVector {
            IntervalVector(
                x: lhs.x - rhs.x,
                y: lhs.y - rhs.y,
                z: lhs.z - rhs.z
            )
        }

        static prefix func - (value: IntervalVector) -> IntervalVector {
            IntervalVector(x: -value.x, y: -value.y, z: -value.z)
        }

        static func * (
            lhs: IntervalVector,
            rhs: OutwardScalarInterval
        ) -> IntervalVector {
            IntervalVector(
                x: lhs.x * rhs,
                y: lhs.y * rhs,
                z: lhs.z * rhs
            )
        }

        func cross(_ other: IntervalVector) -> IntervalVector {
            IntervalVector(
                x: y * other.z - z * other.y,
                y: z * other.x - x * other.z,
                z: x * other.y - y * other.x
            )
        }

        func dot(_ other: IntervalVector) -> OutwardScalarInterval {
            x * other.x + y * other.y + z * other.z
        }

        func union(_ other: IntervalVector) -> IntervalVector {
            IntervalVector(
                x: x.union(other.x),
                y: y.union(other.y),
                z: z.union(other.z)
            )
        }

        var isFinite: Bool {
            x.isFinite && y.isFinite && z.isFinite
        }
    }

    private struct CurveIntervalJet: Sendable {
        let position: IntervalVector
        let firstDerivative: IntervalVector
        let secondDerivative: IntervalVector
        let thirdDerivative: IntervalVector
        let parameters: [ParameterCoordinateIntervalJet]

        func union(_ other: CurveIntervalJet) -> CurveIntervalJet {
            CurveIntervalJet(
                position: position.union(other.position),
                firstDerivative: firstDerivative.union(other.firstDerivative),
                secondDerivative: secondDerivative.union(other.secondDerivative),
                thirdDerivative: thirdDerivative.union(other.thirdDerivative),
                parameters: zip(parameters, other.parameters).map { $0.union($1) }
            )
        }

        var isFinite: Bool {
            position.isFinite
                && firstDerivative.isFinite
                && secondDerivative.isFinite
                && thirdDerivative.isFinite
                && parameters.allSatisfy(\.isFinite)
        }
    }

    private struct ParameterCoordinateIntervalJet: Sendable {
        let value: OutwardScalarInterval
        let firstDerivative: OutwardScalarInterval
        let secondDerivative: OutwardScalarInterval
        let thirdDerivative: OutwardScalarInterval

        func union(
            _ other: ParameterCoordinateIntervalJet
        ) -> ParameterCoordinateIntervalJet {
            ParameterCoordinateIntervalJet(
                value: value.union(other.value),
                firstDerivative: firstDerivative.union(other.firstDerivative),
                secondDerivative: secondDerivative.union(other.secondDerivative),
                thirdDerivative: thirdDerivative.union(other.thirdDerivative)
            )
        }

        var isFinite: Bool {
            value.isFinite
                && firstDerivative.isFinite
                && secondDerivative.isFinite
                && thirdDerivative.isFinite
        }
    }

    private let preparedSurfaces: PreparedSurfaces?

    package init() {
        preparedSurfaces = nil
    }

    package init(
        intersection: CertifiedImplicitIntersectionCurve,
        tolerance: ModelingTolerance
    ) throws {
        let exactIsoparametricGraph = try ExactIsoparametricPlanarIntersectionGraph
            .certified(
                first: intersection.firstSurface,
                second: intersection.secondSurface,
                tolerance: tolerance
            )
        preparedSurfaces = try PreparedSurfaces(
            first: PreparedBSplineSurfaceDifferentialEncloser(
                surface: intersection.firstSurface,
                tolerance: tolerance
            ),
            second: PreparedBSplineSurfaceDifferentialEncloser(
                surface: intersection.secondSurface,
                tolerance: tolerance
            ),
            parameterDerivativeBounds: intersection.cells.map { cell in
                try cell.parameterDerivativeBounds(
                    firstSurface: intersection.firstSurface,
                    secondSurface: intersection.secondSurface,
                    tolerance: tolerance
                )
            },
            exactIsoparametricGraph: exactIsoparametricGraph
        )
    }

    func intervalJet(
        of curve: CertifiedImplicitIntersectionCurve,
        over interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> SurfaceIntervalVectorJet {
        surfaceJet(try enclosedJet(
            of: curve,
            over: interval,
            tolerance: tolerance
        ))
    }

    package func parameterIntervalJet(
        of curve: CertifiedImplicitIntersectionCurve,
        over interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitParameterIntervalJet {
        let jet = try enclosedJet(
            of: curve,
            over: interval,
            tolerance: tolerance
        )
        return CertifiedImplicitParameterIntervalJet(
            coordinates: try jet.parameters.map {
                CertifiedImplicitParameterIntervalJet.Coordinate(
                    value: try scalarInterval($0.value),
                    firstDerivative: try scalarInterval($0.firstDerivative),
                    secondDerivative: try scalarInterval($0.secondDerivative),
                    thirdDerivative: try scalarInterval($0.thirdDerivative)
                )
            }
        )
    }

    package func restrictedBounds(
        of curve: CertifiedImplicitIntersectionCurve,
        cellIndex: Int,
        fromNormalizedFraction lowerFraction: Double,
        toNormalizedFraction upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitIntersectionGraphSubcell {
        guard curve.cells.indices.contains(cellIndex) else {
            throw invalidInput(
                tolerance: tolerance,
                message: "An implicit curve restriction referenced an invalid graph cell."
            )
        }
        let cell = curve.cells[cellIndex]
        if let preparedSurfaces,
           preparedSurfaces.first.surface == curve.firstSurface,
           preparedSurfaces.second.surface == curve.secondSurface,
           preparedSurfaces.parameterDerivativeBounds.indices.contains(cellIndex) {
            if let exact = preparedSurfaces.exactIsoparametricGraph,
               let exactBounds = try exact.restrictedBounds(
                   parameterBox: cell.parameterBox,
                   freeParameter: cell.freeParameter,
                   direction: cell.direction,
                   lowerAnchor: cell.lowerAnchor,
                   midpointAnchor: cell.midpointAnchor,
                   upperAnchor: cell.upperAnchor,
                   fromNormalizedFraction: lowerFraction,
                   toNormalizedFraction: upperFraction,
                   first: curve.firstSurface,
                   second: curve.secondSurface,
                   tolerance: tolerance
               ) {
                return exactBounds
            }
            return try cell.restrictedBounds(
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                firstSurface: curve.firstSurface,
                secondSurface: curve.secondSurface,
                parentDerivativeBounds: preparedSurfaces
                    .parameterDerivativeBounds[cellIndex],
                tolerance: tolerance
            )
        }
        return try cell.restrictedBounds(
            fromNormalizedFraction: lowerFraction,
            toNormalizedFraction: upperFraction,
            firstSurface: curve.firstSurface,
            secondSurface: curve.secondSurface,
            tolerance: tolerance
        )
    }

    private func enclosedJet(
        of curve: CertifiedImplicitIntersectionCurve,
        over interval: ScalarInterval,
        tolerance: ModelingTolerance
    ) throws -> CurveIntervalJet {
        let cellCount = curve.cells.count
        guard cellCount > 0 else {
            throw invalidInput(
                tolerance: tolerance,
                message: "An implicit curve interval jet requires graph cells."
            )
        }
        let count = Double(cellCount)
        var result: CurveIntervalJet?
        for index in curve.cells.indices {
            let cellLower = Double(index) / count
            let cellUpper = Double(index + 1) / count
            let lower = max(interval.lower, cellLower)
            let upper = min(interval.upper, cellUpper)
            guard upper > lower else { continue }
            let local = try enclose(
                curve: curve,
                cellIndex: index,
                globalInterval: ScalarInterval(lower: lower, upper: upper),
                depth: 0,
                tolerance: tolerance
            )
            result = result.map { $0.union(local) } ?? local
        }
        guard let result, result.isFinite else {
            throw certificationFailure(
                tolerance: tolerance,
                message: "An implicit curve interval did not produce a finite third-order jet."
            )
        }
        return result
    }

    private func enclose(
        curve: CertifiedImplicitIntersectionCurve,
        cellIndex: Int,
        globalInterval: ScalarInterval,
        depth: Int,
        tolerance: ModelingTolerance
    ) throws -> CurveIntervalJet {
        let count = Double(curve.cells.count)
        let cell = curve.cells[cellIndex]
        let localLower = max(
            0.0,
            min(1.0, globalInterval.lower * count - Double(cellIndex))
        )
        let localUpper = max(
            0.0,
            min(1.0, globalInterval.upper * count - Double(cellIndex))
        )
        let preparedParentDerivatives: [ScalarInterval]?
        if let preparedSurfaces,
           preparedSurfaces.first.surface == curve.firstSurface,
           preparedSurfaces.second.surface == curve.secondSurface,
           preparedSurfaces.parameterDerivativeBounds.indices.contains(cellIndex) {
            preparedParentDerivatives = preparedSurfaces
                .parameterDerivativeBounds[cellIndex]
        } else {
            preparedParentDerivatives = nil
        }
        let parameterBox: SurfaceIntersectionParameterBox
        let localFirstDerivatives: [ScalarInterval]
        if localUpper - localLower > tolerance.relative {
            let subcell = try restrictedBounds(
                of: curve,
                cellIndex: cellIndex,
                fromNormalizedFraction: localLower,
                toNormalizedFraction: localUpper,
                tolerance: tolerance
            )
            parameterBox = subcell.parameterBox
            let localSpan = localUpper - localLower
            localFirstDerivatives = try subcell.parameterDerivativeBounds.map {
                try ScalarInterval(
                    lower: ($0.lower / localSpan).nextDown,
                    upper: ($0.upper / localSpan).nextUp
                )
            }
        } else {
            parameterBox = cell.parameterBox
            localFirstDerivatives = try preparedParentDerivatives
                ?? cell.parameterDerivativeBounds(
                    firstSurface: curve.firstSurface,
                    secondSurface: curve.secondSurface,
                    tolerance: tolerance
                )
        }
        let firstDerivatives = localFirstDerivatives.map {
            OutwardScalarInterval(lower: $0.lower, upper: $0.upper)
                * OutwardScalarInterval(count)
        }
        let firstParameters = SurfaceParameterBox(
                u: parameterBox.firstU,
                v: parameterBox.firstV
        )
        let secondParameters = SurfaceParameterBox(
                u: parameterBox.secondU,
                v: parameterBox.secondV
        )
        let firstSurface: SurfaceIntervalVectorJet
        let secondSurface: SurfaceIntervalVectorJet
        if let preparedSurfaces,
           preparedSurfaces.first.surface == curve.firstSurface,
           preparedSurfaces.second.surface == curve.secondSurface {
            firstSurface = try preparedSurfaces.first.intervalJet(
                over: firstParameters,
                tolerance: tolerance
            )
            secondSurface = try preparedSurfaces.second.intervalJet(
                over: secondParameters,
                tolerance: tolerance
            )
        } else {
            let encloser = DefaultSurfaceDifferentialEncloser()
            firstSurface = try encloser.intervalJet(
                of: .bSpline(curve.firstSurface),
                over: firstParameters,
                tolerance: tolerance
            )
            secondSurface = try encloser.intervalJet(
                of: .bSpline(curve.secondSurface),
                over: secondParameters,
                tolerance: tolerance
            )
        }
        let columns = [
            vector(firstSurface, at: \SurfaceIntervalJet.derivativeU),
            vector(firstSurface, at: \SurfaceIntervalJet.derivativeV),
            -vector(secondSurface, at: \SurfaceIntervalJet.derivativeU),
            -vector(secondSurface, at: \SurfaceIntervalJet.derivativeV),
        ]
        let freeIndex = cell.freeParameter.rawValue
        let dependentIndexes = columns.indices.filter { $0 != freeIndex }
        let dependentColumns = dependentIndexes.map { columns[$0] }
        let denominator = determinant(dependentColumns)

        if denominator.isFinite, denominator.excludesZero {
            let firstQuadratic = surfaceQuadratic(
                firstSurface,
                derivativeU: firstDerivatives[0],
                derivativeV: firstDerivatives[1]
            )
            let secondQuadratic = surfaceQuadratic(
                secondSurface,
                derivativeU: firstDerivatives[2],
                derivativeV: firstDerivatives[3]
            )
            let secondDerivatives = try solveDependentDerivatives(
                columns: dependentColumns,
                dependentIndexes: dependentIndexes,
                rightHandSide: -(firstQuadratic - secondQuadratic),
                denominator: denominator,
                tolerance: tolerance,
                order: "second"
            )
            let firstCubic = surfaceCubic(
                firstSurface,
                firstU: firstDerivatives[0],
                firstV: firstDerivatives[1],
                secondU: secondDerivatives[0],
                secondV: secondDerivatives[1]
            )
            let secondCubic = surfaceCubic(
                secondSurface,
                firstU: firstDerivatives[2],
                firstV: firstDerivatives[3],
                secondU: secondDerivatives[2],
                secondV: secondDerivatives[3]
            )
            let thirdDerivatives = try solveDependentDerivatives(
                columns: dependentColumns,
                dependentIndexes: dependentIndexes,
                rightHandSide: -(firstCubic - secondCubic),
                denominator: denominator,
                tolerance: tolerance,
                order: "third"
            )
            let firstSpatialFirst = surfaceFirst(
                firstSurface,
                derivativeU: firstDerivatives[0],
                derivativeV: firstDerivatives[1]
            )
            let secondSpatialFirst = surfaceFirst(
                secondSurface,
                derivativeU: firstDerivatives[2],
                derivativeV: firstDerivatives[3]
            )
            let firstSpatialSecond = firstQuadratic
                + vector(firstSurface, at: \SurfaceIntervalJet.derivativeU)
                    * secondDerivatives[0]
                + vector(firstSurface, at: \SurfaceIntervalJet.derivativeV)
                    * secondDerivatives[1]
            let secondSpatialSecond = secondQuadratic
                + vector(secondSurface, at: \SurfaceIntervalJet.derivativeU)
                    * secondDerivatives[2]
                + vector(secondSurface, at: \SurfaceIntervalJet.derivativeV)
                    * secondDerivatives[3]
            let firstSpatialThird = firstCubic
                + vector(firstSurface, at: \SurfaceIntervalJet.derivativeU)
                    * thirdDerivatives[0]
                + vector(firstSurface, at: \SurfaceIntervalJet.derivativeV)
                    * thirdDerivatives[1]
            let secondSpatialThird = secondCubic
                + vector(secondSurface, at: \SurfaceIntervalJet.derivativeU)
                    * thirdDerivatives[2]
                + vector(secondSurface, at: \SurfaceIntervalJet.derivativeV)
                    * thirdDerivatives[3]
            let result = CurveIntervalJet(
                position: averaged(
                    vector(firstSurface, at: \SurfaceIntervalJet.value),
                    vector(secondSurface, at: \SurfaceIntervalJet.value)
                ),
                firstDerivative: averaged(
                    firstSpatialFirst,
                    secondSpatialFirst
                ),
                secondDerivative: averaged(
                    firstSpatialSecond,
                    secondSpatialSecond
                ),
                thirdDerivative: averaged(
                    firstSpatialThird,
                    secondSpatialThird
                ),
                parameters: parameterBox.intervals.indices.map { index in
                    let value = parameterBox.intervals[index]
                    return ParameterCoordinateIntervalJet(
                        value: OutwardScalarInterval(
                            lower: value.lower,
                            upper: value.upper
                        ),
                        firstDerivative: firstDerivatives[index],
                        secondDerivative: secondDerivatives[index],
                        thirdDerivative: thirdDerivatives[index]
                    )
                }
            )
            guard result.isFinite else {
                throw arithmeticFailure(
                    tolerance: tolerance,
                    message: "Implicit curve third-order interval differentiation exceeded finite arithmetic."
                )
            }
            return result
        }

        let scale = max(1.0, abs(globalInterval.lower), abs(globalInterval.upper))
        let minimumWidth = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 4_096.0
        )
        guard depth < 20, globalInterval.width > minimumWidth else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                residual: denominator.absoluteLowerBound,
                tolerance: tolerance,
                message: "Implicit curve third-order certification could not isolate a regular dependent Jacobian."
            )
        }
        let midpoint = globalInterval.midpoint
        let lower = try enclose(
            curve: curve,
            cellIndex: cellIndex,
            globalInterval: ScalarInterval(
                lower: globalInterval.lower,
                upper: midpoint
            ),
            depth: depth + 1,
            tolerance: tolerance
        )
        let upper = try enclose(
            curve: curve,
            cellIndex: cellIndex,
            globalInterval: ScalarInterval(
                lower: midpoint,
                upper: globalInterval.upper
            ),
            depth: depth + 1,
            tolerance: tolerance
        )
        return lower.union(upper)
    }

    private func solveDependentDerivatives(
        columns: [IntervalVector],
        dependentIndexes: [Int],
        rightHandSide: IntervalVector,
        denominator: OutwardScalarInterval,
        tolerance: ModelingTolerance,
        order: String
    ) throws -> [OutwardScalarInterval] {
        var derivatives = Array(
            repeating: OutwardScalarInterval(0.0),
            count: 4
        )
        for dependentOffset in columns.indices {
            var numeratorColumns = columns
            numeratorColumns[dependentOffset] = rightHandSide
            let numerator = determinant(numeratorColumns)
            guard numerator.isFinite,
                  let quotient = numerator.divided(by: denominator),
                  quotient.isFinite else {
                throw arithmeticFailure(
                    tolerance: tolerance,
                    message: "Implicit curve \(order)-order differentiation exceeded finite interval arithmetic."
                )
            }
            derivatives[dependentIndexes[dependentOffset]] = quotient
        }
        return derivatives
    }

    private func surfaceFirst(
        _ enclosure: SurfaceIntervalVectorJet,
        derivativeU: OutwardScalarInterval,
        derivativeV: OutwardScalarInterval
    ) -> IntervalVector {
        vector(enclosure, at: \SurfaceIntervalJet.derivativeU) * derivativeU
            + vector(enclosure, at: \SurfaceIntervalJet.derivativeV) * derivativeV
    }

    private func surfaceQuadratic(
        _ enclosure: SurfaceIntervalVectorJet,
        derivativeU: OutwardScalarInterval,
        derivativeV: OutwardScalarInterval
    ) -> IntervalVector {
        vector(enclosure, at: \SurfaceIntervalJet.secondDerivativeUU)
            * (derivativeU * derivativeU)
            + vector(enclosure, at: \SurfaceIntervalJet.secondDerivativeUV)
                * (OutwardScalarInterval(2.0) * derivativeU * derivativeV)
            + vector(enclosure, at: \SurfaceIntervalJet.secondDerivativeVV)
                * (derivativeV * derivativeV)
    }

    private func surfaceCubic(
        _ enclosure: SurfaceIntervalVectorJet,
        firstU: OutwardScalarInterval,
        firstV: OutwardScalarInterval,
        secondU: OutwardScalarInterval,
        secondV: OutwardScalarInterval
    ) -> IntervalVector {
        let three = OutwardScalarInterval(3.0)
        return vector(enclosure, at: \SurfaceIntervalJet.thirdDerivativeUUU)
            * (firstU * firstU * firstU)
            + vector(enclosure, at: \SurfaceIntervalJet.thirdDerivativeUUV)
                * (three * firstU * firstU * firstV)
            + vector(enclosure, at: \SurfaceIntervalJet.thirdDerivativeUVV)
                * (three * firstU * firstV * firstV)
            + vector(enclosure, at: \SurfaceIntervalJet.thirdDerivativeVVV)
                * (firstV * firstV * firstV)
            + vector(enclosure, at: \SurfaceIntervalJet.secondDerivativeUU)
                * (three * firstU * secondU)
            + vector(enclosure, at: \SurfaceIntervalJet.secondDerivativeUV)
                * (three * (secondU * firstV + firstU * secondV))
            + vector(enclosure, at: \SurfaceIntervalJet.secondDerivativeVV)
                * (three * firstV * secondV)
    }

    private func determinant(_ columns: [IntervalVector]) -> OutwardScalarInterval {
        guard columns.count == 3 else {
            return OutwardScalarInterval(lower: -.infinity, upper: .infinity)
        }
        return columns[0].dot(columns[1].cross(columns[2]))
    }

    private func averaged(
        _ first: IntervalVector,
        _ second: IntervalVector
    ) -> IntervalVector {
        (first + second) * OutwardScalarInterval(0.5)
    }

    private func vector(
        _ jet: SurfaceIntervalVectorJet,
        at keyPath: KeyPath<SurfaceIntervalJet, OutwardScalarInterval>
    ) -> IntervalVector {
        IntervalVector(
            x: jet.x[keyPath: keyPath],
            y: jet.y[keyPath: keyPath],
            z: jet.z[keyPath: keyPath]
        )
    }

    private func surfaceJet(_ jet: CurveIntervalJet) -> SurfaceIntervalVectorJet {
        SurfaceIntervalVectorJet(
            x: surfaceJet(
                position: jet.position.x,
                first: jet.firstDerivative.x,
                second: jet.secondDerivative.x,
                third: jet.thirdDerivative.x
            ),
            y: surfaceJet(
                position: jet.position.y,
                first: jet.firstDerivative.y,
                second: jet.secondDerivative.y,
                third: jet.thirdDerivative.y
            ),
            z: surfaceJet(
                position: jet.position.z,
                first: jet.firstDerivative.z,
                second: jet.secondDerivative.z,
                third: jet.thirdDerivative.z
            )
        )
    }

    private func scalarInterval(
        _ interval: OutwardScalarInterval
    ) throws -> ScalarInterval {
        try ScalarInterval(lower: interval.lower, upper: interval.upper)
    }

    private func surfaceJet(
        position: OutwardScalarInterval,
        first: OutwardScalarInterval,
        second: OutwardScalarInterval,
        third: OutwardScalarInterval
    ) -> SurfaceIntervalJet {
        let zero = OutwardScalarInterval(0.0)
        return SurfaceIntervalJet(
            value: position,
            derivativeU: first,
            derivativeV: zero,
            secondDerivativeUU: second,
            secondDerivativeUV: zero,
            secondDerivativeVV: zero,
            thirdDerivativeUUU: third,
            thirdDerivativeUUV: zero,
            thirdDerivativeUVV: zero,
            thirdDerivativeVVV: zero
        )
    }

    private func invalidInput(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .invalidInput,
            tolerance: tolerance,
            message: message
        )
    }

    private func certificationFailure(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            tolerance: tolerance,
            message: message
        )
    }

    private func arithmeticFailure(
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            tolerance: tolerance,
            message: message
        )
    }
}

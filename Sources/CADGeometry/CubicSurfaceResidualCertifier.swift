import Foundation
import CADCore

struct CubicSurfaceResidualCertifier {
    struct Segment: Sendable {
        let pointControls: [Point3D]
        let firstControls: [Point2D]
        let secondControls: [Point2D]
    }

    struct Result: Sendable {
        let maximumResidualUpperBound: Double
        let certifiedCellCount: Int
    }

    private struct HomogeneousPoint: Sendable {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double

        static let zero = HomogeneousPoint(x: 0.0, y: 0.0, z: 0.0, weight: 0.0)

        static func - (lhs: HomogeneousPoint, rhs: HomogeneousPoint) -> HomogeneousPoint {
            HomogeneousPoint(
                x: lhs.x - rhs.x,
                y: lhs.y - rhs.y,
                z: lhs.z - rhs.z,
                weight: lhs.weight - rhs.weight
            )
        }

        static func * (lhs: HomogeneousPoint, rhs: Double) -> HomogeneousPoint {
            HomogeneousPoint(
                x: lhs.x * rhs,
                y: lhs.y * rhs,
                z: lhs.z * rhs,
                weight: lhs.weight * rhs
            )
        }
    }

    private struct CoordinateMagnitudes: Sendable {
        let x: Double
        let y: Double
        let z: Double
        let weight: Double
    }

    struct SurfaceDerivativeBounds: Sendable {
        let tangentU: Double
        let tangentV: Double
        let secondUU: Double
        let secondUV: Double
        let secondVV: Double

        init(surface: BSplineSurface3D, tolerance: ModelingTolerance) throws {
            try surface.validate(tolerance: tolerance)
            let base = surface.controlPoints.indices.map { rowIndex in
                surface.controlPoints[rowIndex].indices.map { columnIndex in
                    let point = surface.controlPoints[rowIndex][columnIndex]
                    let weight = surface.weights[rowIndex][columnIndex]
                    return HomogeneousPoint(
                        x: point.x * weight,
                        y: point.y * weight,
                        z: point.z * weight,
                        weight: weight
                    )
                }
            }
            let uFirst = try Self.derivativeU(
                base,
                degree: surface.uDegree,
                knots: surface.uKnots,
                tolerance: tolerance
            )
            let vFirst = try Self.derivativeV(
                base,
                degree: surface.vDegree,
                knots: surface.vKnots,
                tolerance: tolerance
            )
            let uSecond = try Self.derivativeU(
                uFirst,
                degree: surface.uDegree - 1,
                knots: Array(surface.uKnots.dropFirst().dropLast()),
                tolerance: tolerance
            )
            let uvSecond = try Self.derivativeV(
                uFirst,
                degree: surface.vDegree,
                knots: surface.vKnots,
                tolerance: tolerance
            )
            let vSecond = try Self.derivativeV(
                vFirst,
                degree: surface.vDegree - 1,
                knots: Array(surface.vKnots.dropFirst().dropLast()),
                tolerance: tolerance
            )

            let baseMagnitude = Self.coordinateMagnitudes(base)
            let uFirstMagnitude = Self.coordinateMagnitudes(uFirst)
            let vFirstMagnitude = Self.coordinateMagnitudes(vFirst)
            let uSecondMagnitude = Self.coordinateMagnitudes(uSecond)
            let uvSecondMagnitude = Self.coordinateMagnitudes(uvSecond)
            let vSecondMagnitude = Self.coordinateMagnitudes(vSecond)
            guard let minimumWeightValue = surface.weights.flatMap({ $0 }).min() else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Surface derivative certification requires positive weights."
                )
            }
            let minimumWeight = minimumWeightValue.nextDown
            guard minimumWeight.isFinite, minimumWeight > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: minimumWeight,
                    tolerance: tolerance,
                    message: "Surface derivative certification could not bound the rational denominator away from zero."
                )
            }
            let weightSquared = try Self.lowerProduct(minimumWeight, minimumWeight, tolerance: tolerance)
            let weightCubed = try Self.lowerProduct(weightSquared, minimumWeight, tolerance: tolerance)

            let firstUComponents = try Self.firstDerivativeComponents(
                base: baseMagnitude,
                first: uFirstMagnitude,
                minimumWeight: minimumWeight,
                weightSquared: weightSquared,
                tolerance: tolerance
            )
            let firstVComponents = try Self.firstDerivativeComponents(
                base: baseMagnitude,
                first: vFirstMagnitude,
                minimumWeight: minimumWeight,
                weightSquared: weightSquared,
                tolerance: tolerance
            )
            let secondUUComponents = try Self.secondDerivativeComponents(
                base: baseMagnitude,
                firstA: uFirstMagnitude,
                firstB: uFirstMagnitude,
                second: uSecondMagnitude,
                minimumWeight: minimumWeight,
                weightSquared: weightSquared,
                weightCubed: weightCubed,
                tolerance: tolerance
            )
            let secondUVComponents = try Self.secondDerivativeComponents(
                base: baseMagnitude,
                firstA: uFirstMagnitude,
                firstB: vFirstMagnitude,
                second: uvSecondMagnitude,
                minimumWeight: minimumWeight,
                weightSquared: weightSquared,
                weightCubed: weightCubed,
                tolerance: tolerance
            )
            let secondVVComponents = try Self.secondDerivativeComponents(
                base: baseMagnitude,
                firstA: vFirstMagnitude,
                firstB: vFirstMagnitude,
                second: vSecondMagnitude,
                minimumWeight: minimumWeight,
                weightSquared: weightSquared,
                weightCubed: weightCubed,
                tolerance: tolerance
            )
            tangentU = try Self.vectorMagnitude(firstUComponents, tolerance: tolerance)
            tangentV = try Self.vectorMagnitude(firstVComponents, tolerance: tolerance)
            secondUU = try Self.vectorMagnitude(secondUUComponents, tolerance: tolerance)
            secondUV = try Self.vectorMagnitude(secondUVComponents, tolerance: tolerance)
            secondVV = try Self.vectorMagnitude(secondVVComponents, tolerance: tolerance)
        }

        private static func derivativeU(
            _ values: [[HomogeneousPoint]],
            degree: Int,
            knots: [Double],
            tolerance: ModelingTolerance
        ) throws -> [[HomogeneousPoint]] {
            guard degree > 0 else {
                return values.map { row in row.map { _ in .zero } }
            }
            return try values.map { row in
                guard row.count >= 2 else {
                    throw KernelError(
                        phase: .geometry,
                        code: .invalidInput,
                        tolerance: tolerance,
                        message: "Surface derivative certification requires at least two U control points."
                    )
                }
                return try (0..<(row.count - 1)).map { index in
                    let denominator = knots[index + degree + 1] - knots[index + 1]
                    let difference = row[index + 1] - row[index]
                    guard denominator.isFinite else {
                        throw KernelError(
                            phase: .geometry,
                            code: .singularSystem,
                            residual: denominator,
                            tolerance: tolerance,
                            message: "Surface U derivative control interval collapsed."
                        )
                    }
                    if denominator == 0.0 {
                        return .zero
                    }
                    guard denominator > 0.0 else {
                        throw KernelError(
                            phase: .geometry,
                            code: .singularSystem,
                            residual: denominator,
                            tolerance: tolerance,
                            message: "Surface U derivative control interval collapsed."
                        )
                    }
                    return difference * (Double(degree) / denominator)
                }
            }
        }

        private static func derivativeV(
            _ values: [[HomogeneousPoint]],
            degree: Int,
            knots: [Double],
            tolerance: ModelingTolerance
        ) throws -> [[HomogeneousPoint]] {
            guard degree > 0 else {
                return values.map { row in row.map { _ in .zero } }
            }
            guard values.count >= 2, let columnCount = values.first?.count else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Surface derivative certification requires at least two V control points."
                )
            }
            return try (0..<(values.count - 1)).map { rowIndex in
                let denominator = knots[rowIndex + degree + 1] - knots[rowIndex + 1]
                guard denominator.isFinite else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularSystem,
                        residual: denominator,
                        tolerance: tolerance,
                        message: "Surface V derivative control interval collapsed."
                    )
                }
                if denominator == 0.0 {
                    return Array(repeating: .zero, count: columnCount)
                }
                guard denominator > 0.0 else {
                    throw KernelError(
                        phase: .geometry,
                        code: .singularSystem,
                        residual: denominator,
                        tolerance: tolerance,
                        message: "Surface V derivative control interval collapsed."
                    )
                }
                let factor = Double(degree) / denominator
                return (0..<columnCount).map { columnIndex in
                    (values[rowIndex + 1][columnIndex]
                        - values[rowIndex][columnIndex]) * factor
                }
            }
        }

        private static func coordinateMagnitudes(
            _ values: [[HomogeneousPoint]]
        ) -> CoordinateMagnitudes {
            var result = CoordinateMagnitudes(x: 0.0, y: 0.0, z: 0.0, weight: 0.0)
            for value in values.flatMap({ $0 }) {
                result = CoordinateMagnitudes(
                    x: max(result.x, abs(value.x).nextUp),
                    y: max(result.y, abs(value.y).nextUp),
                    z: max(result.z, abs(value.z).nextUp),
                    weight: max(result.weight, abs(value.weight).nextUp)
                )
            }
            return result
        }

        private static func firstDerivativeComponents(
            base: CoordinateMagnitudes,
            first: CoordinateMagnitudes,
            minimumWeight: Double,
            weightSquared: Double,
            tolerance: ModelingTolerance
        ) throws -> CoordinateMagnitudes {
            try CoordinateMagnitudes(
                x: firstDerivativeComponent(
                    base: base.x,
                    first: first.x,
                    weightFirst: first.weight,
                    minimumWeight: minimumWeight,
                    weightSquared: weightSquared,
                    tolerance: tolerance
                ),
                y: firstDerivativeComponent(
                    base: base.y,
                    first: first.y,
                    weightFirst: first.weight,
                    minimumWeight: minimumWeight,
                    weightSquared: weightSquared,
                    tolerance: tolerance
                ),
                z: firstDerivativeComponent(
                    base: base.z,
                    first: first.z,
                    weightFirst: first.weight,
                    minimumWeight: minimumWeight,
                    weightSquared: weightSquared,
                    tolerance: tolerance
                ),
                weight: 0.0
            )
        }

        private static func firstDerivativeComponent(
            base: Double,
            first: Double,
            weightFirst: Double,
            minimumWeight: Double,
            weightSquared: Double,
            tolerance: ModelingTolerance
        ) throws -> Double {
            try upperSum([
                try upperQuotient(first, minimumWeight, tolerance: tolerance),
                try upperQuotient(
                    try upperProduct(base, weightFirst, tolerance: tolerance),
                    weightSquared,
                    tolerance: tolerance
                ),
            ], tolerance: tolerance)
        }

        private static func secondDerivativeComponents(
            base: CoordinateMagnitudes,
            firstA: CoordinateMagnitudes,
            firstB: CoordinateMagnitudes,
            second: CoordinateMagnitudes,
            minimumWeight: Double,
            weightSquared: Double,
            weightCubed: Double,
            tolerance: ModelingTolerance
        ) throws -> CoordinateMagnitudes {
            try CoordinateMagnitudes(
                x: secondDerivativeComponent(
                    base: base.x,
                    firstA: firstA.x,
                    firstB: firstB.x,
                    weightFirstA: firstA.weight,
                    weightFirstB: firstB.weight,
                    second: second.x,
                    weightSecond: second.weight,
                    minimumWeight: minimumWeight,
                    weightSquared: weightSquared,
                    weightCubed: weightCubed,
                    tolerance: tolerance
                ),
                y: secondDerivativeComponent(
                    base: base.y,
                    firstA: firstA.y,
                    firstB: firstB.y,
                    weightFirstA: firstA.weight,
                    weightFirstB: firstB.weight,
                    second: second.y,
                    weightSecond: second.weight,
                    minimumWeight: minimumWeight,
                    weightSquared: weightSquared,
                    weightCubed: weightCubed,
                    tolerance: tolerance
                ),
                z: secondDerivativeComponent(
                    base: base.z,
                    firstA: firstA.z,
                    firstB: firstB.z,
                    weightFirstA: firstA.weight,
                    weightFirstB: firstB.weight,
                    second: second.z,
                    weightSecond: second.weight,
                    minimumWeight: minimumWeight,
                    weightSquared: weightSquared,
                    weightCubed: weightCubed,
                    tolerance: tolerance
                ),
                weight: 0.0
            )
        }

        private static func secondDerivativeComponent(
            base: Double,
            firstA: Double,
            firstB: Double,
            weightFirstA: Double,
            weightFirstB: Double,
            second: Double,
            weightSecond: Double,
            minimumWeight: Double,
            weightSquared: Double,
            weightCubed: Double,
            tolerance: ModelingTolerance
        ) throws -> Double {
            let firstCross = try upperSum([
                try upperProduct(firstA, weightFirstB, tolerance: tolerance),
                try upperProduct(firstB, weightFirstA, tolerance: tolerance),
            ], tolerance: tolerance)
            let weightCross = try upperProduct(
                weightFirstA,
                weightFirstB,
                tolerance: tolerance
            )
            return try upperSum([
                try upperQuotient(second, minimumWeight, tolerance: tolerance),
                try upperQuotient(
                    firstCross,
                    weightSquared,
                    tolerance: tolerance
                ),
                try upperQuotient(
                    try upperProduct(base, weightSecond, tolerance: tolerance),
                    weightSquared,
                    tolerance: tolerance
                ),
                try upperQuotient(
                    try upperProduct(
                        2.0,
                        try upperProduct(base, weightCross, tolerance: tolerance),
                        tolerance: tolerance
                    ),
                    weightCubed,
                    tolerance: tolerance
                ),
            ], tolerance: tolerance)
        }

        private static func vectorMagnitude(
            _ components: CoordinateMagnitudes,
            tolerance: ModelingTolerance
        ) throws -> Double {
            let squared = try upperSum([
                try upperProduct(components.x, components.x, tolerance: tolerance),
                try upperProduct(components.y, components.y, tolerance: tolerance),
                try upperProduct(components.z, components.z, tolerance: tolerance),
            ], tolerance: tolerance)
            let value = sqrt(squared).nextUp
            guard value.isFinite else {
                throw resourceLimit(
                    residual: value,
                    tolerance: tolerance,
                    message: "Surface derivative magnitude bound overflowed."
                )
            }
            return value
        }

        private static func lowerProduct(
            _ first: Double,
            _ second: Double,
            tolerance: ModelingTolerance
        ) throws -> Double {
            let value = (first * second).nextDown
            guard value.isFinite, value > 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    residual: value,
                    tolerance: tolerance,
                    message: "Surface derivative denominator bound collapsed."
                )
            }
            return value
        }

        private static func upperProduct(
            _ first: Double,
            _ second: Double,
            tolerance: ModelingTolerance
        ) throws -> Double {
            let value = (first * second).nextUp
            guard value.isFinite, value >= 0.0 else {
                throw resourceLimit(
                    residual: value,
                    tolerance: tolerance,
                    message: "Surface derivative product bound overflowed."
                )
            }
            return value
        }

        private static func upperQuotient(
            _ numerator: Double,
            _ denominator: Double,
            tolerance: ModelingTolerance
        ) throws -> Double {
            let value = (numerator / denominator).nextUp
            guard value.isFinite, value >= 0.0 else {
                throw resourceLimit(
                    residual: value,
                    tolerance: tolerance,
                    message: "Surface derivative quotient bound overflowed."
                )
            }
            return value
        }

        private static func upperSum(
            _ values: [Double],
            tolerance: ModelingTolerance
        ) throws -> Double {
            var result = 0.0
            for value in values {
                result = (result + value).nextUp
                guard result.isFinite, result >= 0.0 else {
                    throw resourceLimit(
                        residual: result,
                        tolerance: tolerance,
                        message: "Surface derivative sum bound overflowed."
                    )
                }
            }
            return result
        }
    }

    private struct CubicCell: Sendable {
        let points: [Point3D]
        let firstParameters: [Point2D]
        let secondParameters: [Point2D]
        let depth: Int
    }

    private struct CellBound: Sendable {
        let observedResidual: Double
        let residualUpperBound: Double
        let requiresParameterSubdivision: Bool
    }

    private struct OutwardInterval: Sendable {
        let lower: Double
        let upper: Double

        init(_ value: Double) {
            lower = value.nextDown
            upper = value.nextUp
        }

        private init(lower: Double, upper: Double) {
            self.lower = lower
            self.upper = upper
        }

        static let zero = OutwardInterval(0.0)
        static let one = OutwardInterval(1.0)

        static func + (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            OutwardInterval(
                lower: (lhs.lower + rhs.lower).nextDown,
                upper: (lhs.upper + rhs.upper).nextUp
            )
        }

        static func - (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            OutwardInterval(
                lower: (lhs.lower - rhs.upper).nextDown,
                upper: (lhs.upper - rhs.lower).nextUp
            )
        }

        static func * (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            let products = [
                lhs.lower * rhs.lower,
                lhs.lower * rhs.upper,
                lhs.upper * rhs.lower,
                lhs.upper * rhs.upper,
            ]
            return OutwardInterval(
                lower: (products.min() ?? -.infinity).nextDown,
                upper: (products.max() ?? .infinity).nextUp
            )
        }

        static func / (lhs: OutwardInterval, rhs: OutwardInterval) -> OutwardInterval {
            guard rhs.lower > 0.0 else {
                return OutwardInterval(lower: -.infinity, upper: .infinity)
            }
            let reciprocal = OutwardInterval(
                lower: (1.0 / rhs.upper).nextDown,
                upper: (1.0 / rhs.lower).nextUp
            )
            return lhs * reciprocal
        }

        var absoluteUpperBound: Double {
            max(abs(lower), abs(upper)).nextUp
        }
    }

    private struct IntervalVector: Sendable {
        let x: OutwardInterval
        let y: OutwardInterval
        let z: OutwardInterval

        static let zero = IntervalVector(x: .zero, y: .zero, z: .zero)

        init(point: Point3D) {
            x = OutwardInterval(point.x)
            y = OutwardInterval(point.y)
            z = OutwardInterval(point.z)
        }

        init(x: OutwardInterval, y: OutwardInterval, z: OutwardInterval) {
            self.x = x
            self.y = y
            self.z = z
        }

        static func + (lhs: IntervalVector, rhs: IntervalVector) -> IntervalVector {
            IntervalVector(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
        }

        static func - (lhs: IntervalVector, rhs: IntervalVector) -> IntervalVector {
            IntervalVector(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
        }

        static func * (lhs: IntervalVector, rhs: OutwardInterval) -> IntervalVector {
            IntervalVector(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
        }

        var lengthUpperBound: Double {
            let xBound = x.absoluteUpperBound
            let yBound = y.absoluteUpperBound
            let zBound = z.absoluteUpperBound
            return sqrt(
                xBound * xBound + yBound * yBound + zBound * zBound
            ).nextUp
        }
    }

    func certify(
        pointControls: [Point3D],
        firstControls: [Point2D],
        secondControls: [Point2D],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Result {
        try certify(
            segments: [Segment(
                pointControls: pointControls,
                firstControls: firstControls,
                secondControls: secondControls
            )],
            first: first,
            second: second,
            options: options,
            tolerance: tolerance
        )
    }

    func certify(
        segments: [Segment],
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        options: SurfaceSurfaceIntersectionOptions,
        tolerance: ModelingTolerance
    ) throws -> Result {
        try options.validate(tolerance: tolerance)
        guard segments.isEmpty == false,
              segments.allSatisfy({
                  $0.pointControls.count == 4
                      && $0.firstControls.count == 4
                      && $0.secondControls.count == 4
              }) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "Cubic surface residual certification requires four control points per curve."
            )
        }
        let firstBounds = try SurfaceDerivativeBounds(surface: first, tolerance: tolerance)
        let secondBounds = try SurfaceDerivativeBounds(surface: second, tolerance: tolerance)
        var stack = segments.reversed().map {
            CubicCell(
                points: $0.pointControls,
                firstParameters: $0.firstControls,
                secondParameters: $0.secondControls,
                depth: 0
            )
        }
        var remainingCells = options.maximumResidualCertificationCells
        var certifiedCellCount = 0
        var maximumResidualUpperBound = 0.0
        while let cell = stack.popLast() {
            guard remainingCells > 0 else {
                throw resourceLimit(
                    residual: maximumResidualUpperBound,
                    tolerance: tolerance,
                    message: "Cubic surface residual certification exceeded its cell budget."
                )
            }
            remainingCells -= 1
            let bound = try cellBound(
                cell,
                first: first,
                second: second,
                firstBounds: firstBounds,
                secondBounds: secondBounds,
                tolerance: tolerance
            )
            if bound.requiresParameterSubdivision == false,
               bound.residualUpperBound <= tolerance.distance {
                maximumResidualUpperBound = max(
                    maximumResidualUpperBound,
                    bound.residualUpperBound
                )
                certifiedCellCount += 1
                continue
            }
            if bound.observedResidual > tolerance.distance {
                throw KernelError(
                    phase: .geometry,
                    code: .intersectionFailure,
                    residual: bound.observedResidual,
                    tolerance: tolerance,
                    message: "Composite cubic surface intersection exceeds the requested tolerance."
                )
            }
            guard cell.depth < options.maximumResidualCertificationDepth else {
                throw resourceLimit(
                    residual: bound.residualUpperBound,
                    tolerance: tolerance,
                    message: "Cubic surface residual certification exceeded its subdivision depth."
                )
            }
            let halves = subdivided(cell)
            stack.append(halves.upper)
            stack.append(halves.lower)
        }
        return Result(
            maximumResidualUpperBound: maximumResidualUpperBound,
            certifiedCellCount: certifiedCellCount
        )
    }

    private func cellBound(
        _ cell: CubicCell,
        first: BSplineSurface3D,
        second: BSplineSurface3D,
        firstBounds: SurfaceDerivativeBounds,
        secondBounds: SurfaceDerivativeBounds,
        tolerance: ModelingTolerance
    ) throws -> CellBound {
        let requiresParameterSubdivision = parameterControlsAreContained(
            cell.firstParameters,
            surface: first,
            tolerance: tolerance
        ) == false || parameterControlsAreContained(
            cell.secondParameters,
            surface: second,
            tolerance: tolerance
        ) == false
        if requiresParameterSubdivision {
            return CellBound(
                observedResidual: 0.0,
                residualUpperBound: Double.greatestFiniteMagnitude,
                requiresParameterSubdivision: true
            )
        }
        if let polynomialUpperBound = polynomialResidualUpperBound(
            cell,
            first: first,
            second: second
        ), polynomialUpperBound <= tolerance.distance {
            return CellBound(
                observedResidual: polynomialUpperBound,
                residualUpperBound: polynomialUpperBound,
                requiresParameterSubdivision: false
            )
        }

        let fraction = 0.5
        let curvePoint = cubicPoint(cell.points, fraction: fraction)
        let curveDerivative = cubicDerivative(cell.points, fraction: fraction)
        let firstUV = cubicPoint(cell.firstParameters, fraction: fraction)
        let firstUVDerivative = cubicDerivative(cell.firstParameters, fraction: fraction)
        let secondUV = cubicPoint(cell.secondParameters, fraction: fraction)
        let secondUVDerivative = cubicDerivative(cell.secondParameters, fraction: fraction)
        let firstGeometry = try first.differentialGeometry(
            atU: firstUV.x,
            v: firstUV.y,
            tolerance: tolerance
        )
        let secondGeometry = try second.differentialGeometry(
            atU: secondUV.x,
            v: secondUV.y,
            tolerance: tolerance
        )
        let firstDerivative = firstGeometry.tangentU * firstUVDerivative.x
            + firstGeometry.tangentV * firstUVDerivative.y
        let secondDerivative = secondGeometry.tangentU * secondUVDerivative.x
            + secondGeometry.tangentV * secondUVDerivative.y
        let firstResidual = outwardLength(curvePoint - firstGeometry.position)
        let secondResidual = outwardLength(curvePoint - secondGeometry.position)
        let mutualResidual = outwardLength(firstGeometry.position - secondGeometry.position)
        let observedResidual = max(firstResidual, secondResidual, mutualResidual)

        let curveSecondBound = cubicSecondDerivativeBound(cell.points)
        let firstSurfaceSecondBound = try surfaceSecondDerivativeBound(
            controls: cell.firstParameters,
            bounds: firstBounds,
            tolerance: tolerance
        )
        let secondSurfaceSecondBound = try surfaceSecondDerivativeBound(
            controls: cell.secondParameters,
            bounds: secondBounds,
            tolerance: tolerance
        )
        let firstUpper = try taylorUpperBound(
            residual: firstResidual,
            derivativeResidual: outwardLength(curveDerivative - firstDerivative),
            secondDerivativeBound: try upperSum(
                [curveSecondBound, firstSurfaceSecondBound],
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let secondUpper = try taylorUpperBound(
            residual: secondResidual,
            derivativeResidual: outwardLength(curveDerivative - secondDerivative),
            secondDerivativeBound: try upperSum(
                [curveSecondBound, secondSurfaceSecondBound],
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        let mutualUpper = try taylorUpperBound(
            residual: mutualResidual,
            derivativeResidual: outwardLength(firstDerivative - secondDerivative),
            secondDerivativeBound: try upperSum(
                [firstSurfaceSecondBound, secondSurfaceSecondBound],
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
        return CellBound(
            observedResidual: observedResidual,
            residualUpperBound: max(firstUpper, secondUpper, mutualUpper),
            requiresParameterSubdivision: false
        )
    }

    private func polynomialResidualUpperBound(
        _ cell: CubicCell,
        first: BSplineSurface3D,
        second: BSplineSurface3D
    ) -> Double? {
        guard let firstComposition = polynomialSurfaceComposition(
            surface: first,
            parameterControls: cell.firstParameters
        ), let secondComposition = polynomialSurfaceComposition(
            surface: second,
            parameterControls: cell.secondParameters
        ) else {
            return nil
        }
        let targetDegree = max(
            3,
            max(firstComposition.count - 1, secondComposition.count - 1)
        )
        let points = elevated(
            cell.points.map(IntervalVector.init(point:)),
            to: targetDegree
        )
        let firstValues = elevated(firstComposition, to: targetDegree)
        let secondValues = elevated(secondComposition, to: targetDegree)
        guard points.count == firstValues.count,
              points.count == secondValues.count else {
            return nil
        }
        var result = 0.0
        for index in points.indices {
            result = max(result, max(
                (points[index] - firstValues[index]).lengthUpperBound,
                max(
                    (points[index] - secondValues[index]).lengthUpperBound,
                    (firstValues[index] - secondValues[index]).lengthUpperBound
                )
            ))
        }
        return result.nextUp
    }

    private func polynomialSurfaceComposition(
        surface: BSplineSurface3D,
        parameterControls: [Point2D]
    ) -> [IntervalVector]? {
        guard isSinglePolynomialBezier(surface),
              parameterControls.count == 4,
              surface.uDegree + surface.vDegree <= 12 else {
            return nil
        }
        let uBounds = closedBounds(surface.uDomain)
        let vBounds = closedBounds(surface.vDomain)
        let uSpan = uBounds.upper - uBounds.lower
        let vSpan = vBounds.upper - vBounds.lower
        guard uSpan.isFinite, uSpan > 0.0,
              vSpan.isFinite, vSpan > 0.0 else {
            return nil
        }
        let uSpanInterval = OutwardInterval(uBounds.upper) - OutwardInterval(uBounds.lower)
        let vSpanInterval = OutwardInterval(vBounds.upper) - OutwardInterval(vBounds.lower)
        let u = parameterControls.map {
            (OutwardInterval($0.x) - OutwardInterval(uBounds.lower)) / uSpanInterval
        }
        let v = parameterControls.map {
            (OutwardInterval($0.y) - OutwardInterval(vBounds.lower)) / vSpanInterval
        }
        let uBasis = (0...surface.uDegree).map {
            bernsteinBasis(index: $0, degree: surface.uDegree, parameter: u)
        }
        let vBasis = (0...surface.vDegree).map {
            bernsteinBasis(index: $0, degree: surface.vDegree, parameter: v)
        }
        let resultDegree = 3 * (surface.uDegree + surface.vDegree)
        var result = Array(repeating: IntervalVector.zero, count: resultDegree + 1)
        for vIndex in 0...surface.vDegree {
            for uIndex in 0...surface.uDegree {
                let basisProduct = multipliedBernstein(
                    uBasis[uIndex],
                    vBasis[vIndex]
                )
                let control = IntervalVector(
                    point: surface.controlPoints[vIndex][uIndex]
                )
                for index in basisProduct.indices {
                    result[index] = result[index] + control * basisProduct[index]
                }
            }
        }
        guard result.allSatisfy({
            $0.x.lower.isFinite && $0.x.upper.isFinite
                && $0.y.lower.isFinite && $0.y.upper.isFinite
                && $0.z.lower.isFinite && $0.z.upper.isFinite
        }) else {
            return nil
        }
        return result
    }

    private func isSinglePolynomialBezier(_ surface: BSplineSurface3D) -> Bool {
        guard surface.controlPoints.count == surface.vDegree + 1,
              surface.controlPoints.allSatisfy({ $0.count == surface.uDegree + 1 }),
              surface.uKnots.count == 2 * (surface.uDegree + 1),
              surface.vKnots.count == 2 * (surface.vDegree + 1),
              let firstWeight = surface.weights.first?.first,
              surface.weights.flatMap({ $0 }).allSatisfy({ $0 == firstWeight }) else {
            return false
        }
        let uLower = surface.uKnots[0]
        let uUpper = surface.uKnots[surface.uKnots.count - 1]
        let vLower = surface.vKnots[0]
        let vUpper = surface.vKnots[surface.vKnots.count - 1]
        return surface.uKnots.prefix(surface.uDegree + 1).allSatisfy { $0 == uLower }
            && surface.uKnots.suffix(surface.uDegree + 1).allSatisfy { $0 == uUpper }
            && surface.vKnots.prefix(surface.vDegree + 1).allSatisfy { $0 == vLower }
            && surface.vKnots.suffix(surface.vDegree + 1).allSatisfy { $0 == vUpper }
    }

    private func bernsteinBasis(
        index: Int,
        degree: Int,
        parameter: [OutwardInterval]
    ) -> [OutwardInterval] {
        let complement = parameter.map { OutwardInterval.one - $0 }
        let parameterPower = bernsteinPower(parameter, exponent: index)
        let complementPower = bernsteinPower(complement, exponent: degree - index)
        let product = multipliedBernstein(parameterPower, complementPower)
        let coefficient = OutwardInterval(binomial(degree, index))
        return product.map { $0 * coefficient }
    }

    private func bernsteinPower(
        _ values: [OutwardInterval],
        exponent: Int
    ) -> [OutwardInterval] {
        guard exponent > 0 else { return [.one] }
        return (1..<exponent).reduce(values) { result, _ in
            multipliedBernstein(result, values)
        }
    }

    private func multipliedBernstein(
        _ first: [OutwardInterval],
        _ second: [OutwardInterval]
    ) -> [OutwardInterval] {
        let firstDegree = first.count - 1
        let secondDegree = second.count - 1
        let resultDegree = firstDegree + secondDegree
        var result = Array(repeating: OutwardInterval.zero, count: resultDegree + 1)
        for firstIndex in first.indices {
            for secondIndex in second.indices {
                let resultIndex = firstIndex + secondIndex
                let factor = OutwardInterval(binomial(firstDegree, firstIndex))
                    * OutwardInterval(binomial(secondDegree, secondIndex))
                    / OutwardInterval(binomial(resultDegree, resultIndex))
                result[resultIndex] = result[resultIndex]
                    + first[firstIndex]
                    * second[secondIndex]
                    * factor
            }
        }
        return result
    }

    private func binomial(_ degree: Int, _ index: Int) -> Double {
        guard index > 0, index < degree else { return 1.0 }
        let reducedIndex = min(index, degree - index)
        return (1...reducedIndex).reduce(1.0) { result, value in
            result * Double(degree - reducedIndex + value) / Double(value)
        }
    }

    private func elevated(
        _ controls: [IntervalVector],
        to targetDegree: Int
    ) -> [IntervalVector] {
        var result = controls
        while result.count - 1 < targetDegree {
            let degree = result.count - 1
            var elevated = [result[0]]
            for index in 1...degree {
                let incoming = OutwardInterval(Double(index) / Double(degree + 1))
                let outgoing = OutwardInterval(1.0 - Double(index) / Double(degree + 1))
                elevated.append(result[index - 1] * incoming + result[index] * outgoing)
            }
            elevated.append(result[degree])
            result = elevated
        }
        return result
    }

    private func surfaceSecondDerivativeBound(
        controls: [Point2D],
        bounds: SurfaceDerivativeBounds,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let first = cubicParameterDerivativeMagnitudes(controls)
        let second = cubicParameterSecondDerivativeMagnitudes(controls)
        return try upperSum([
            try upperProduct(
                bounds.secondUU,
                try upperProduct(first.x, first.x, tolerance: tolerance),
                tolerance: tolerance
            ),
            try upperProduct(
                2.0,
                try upperProduct(
                    bounds.secondUV,
                    try upperProduct(first.x, first.y, tolerance: tolerance),
                    tolerance: tolerance
                ),
                tolerance: tolerance
            ),
            try upperProduct(
                bounds.secondVV,
                try upperProduct(first.y, first.y, tolerance: tolerance),
                tolerance: tolerance
            ),
            try upperProduct(bounds.tangentU, second.x, tolerance: tolerance),
            try upperProduct(bounds.tangentV, second.y, tolerance: tolerance),
        ], tolerance: tolerance)
    }

    private func taylorUpperBound(
        residual: Double,
        derivativeResidual: Double,
        secondDerivativeBound: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try upperSum([
            residual,
            try upperProduct(derivativeResidual, 0.5, tolerance: tolerance),
            try upperProduct(secondDerivativeBound, 0.125, tolerance: tolerance),
        ], tolerance: tolerance)
    }

    private func parameterControlsAreContained(
        _ controls: [Point2D],
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) -> Bool {
        let u = closedBounds(surface.uDomain)
        let v = closedBounds(surface.vDomain)
        return controls.allSatisfy {
            $0.x.isFinite && $0.y.isFinite
                && $0.x >= u.lower - tolerance.distance
                && $0.x <= u.upper + tolerance.distance
                && $0.y >= v.lower - tolerance.distance
                && $0.y <= v.upper + tolerance.distance
        }
    }

    private func closedBounds(_ domain: ParameterDomain) -> (lower: Double, upper: Double) {
        switch domain {
        case let .closed(lower, upper):
            return (lower, upper)
        case .periodic, .unbounded:
            return (0.0, 0.0)
        }
    }

    private func subdivided(_ cell: CubicCell) -> (lower: CubicCell, upper: CubicCell) {
        let pointHalves = split(cell.points)
        let firstHalves = split(cell.firstParameters)
        let secondHalves = split(cell.secondParameters)
        return (
            CubicCell(
                points: pointHalves.lower,
                firstParameters: firstHalves.lower,
                secondParameters: secondHalves.lower,
                depth: cell.depth + 1
            ),
            CubicCell(
                points: pointHalves.upper,
                firstParameters: firstHalves.upper,
                secondParameters: secondHalves.upper,
                depth: cell.depth + 1
            )
        )
    }

    private func split(_ values: [Point3D]) -> (lower: [Point3D], upper: [Point3D]) {
        var levels = [values]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                midpoint(previous[index], previous[index + 1])
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private func split(_ values: [Point2D]) -> (lower: [Point2D], upper: [Point2D]) {
        var levels = [values]
        while let previous = levels.last, previous.count > 1 {
            levels.append((0..<(previous.count - 1)).map { index in
                midpoint(previous[index], previous[index + 1])
            })
        }
        return (
            levels.map { $0[0] },
            levels.reversed().map { $0[$0.count - 1] }
        )
    }

    private func midpoint(_ first: Point3D, _ second: Point3D) -> Point3D {
        Point3D(
            x: first.x + (second.x - first.x) * 0.5,
            y: first.y + (second.y - first.y) * 0.5,
            z: first.z + (second.z - first.z) * 0.5
        )
    }

    private func midpoint(_ first: Point2D, _ second: Point2D) -> Point2D {
        Point2D(
            x: first.x + (second.x - first.x) * 0.5,
            y: first.y + (second.y - first.y) * 0.5
        )
    }

    private func cubicPoint(_ controls: [Point3D], fraction: Double) -> Point3D {
        let weights = cubicWeights(fraction: fraction)
        return Point3D(
            x: zip(controls, weights).reduce(0.0) { $0 + $1.0.x * $1.1 },
            y: zip(controls, weights).reduce(0.0) { $0 + $1.0.y * $1.1 },
            z: zip(controls, weights).reduce(0.0) { $0 + $1.0.z * $1.1 }
        )
    }

    private func cubicPoint(_ controls: [Point2D], fraction: Double) -> Point2D {
        let weights = cubicWeights(fraction: fraction)
        return Point2D(
            x: zip(controls, weights).reduce(0.0) { $0 + $1.0.x * $1.1 },
            y: zip(controls, weights).reduce(0.0) { $0 + $1.0.y * $1.1 }
        )
    }

    private func cubicDerivative(_ controls: [Point3D], fraction: Double) -> Vector3D {
        let complement = 1.0 - fraction
        return (controls[1] - controls[0]) * (3.0 * complement * complement)
            + (controls[2] - controls[1]) * (6.0 * complement * fraction)
            + (controls[3] - controls[2]) * (3.0 * fraction * fraction)
    }

    private func cubicDerivative(_ controls: [Point2D], fraction: Double) -> Point2D {
        let complement = 1.0 - fraction
        return Point2D(
            x: (controls[1].x - controls[0].x) * (3.0 * complement * complement)
                + (controls[2].x - controls[1].x) * (6.0 * complement * fraction)
                + (controls[3].x - controls[2].x) * (3.0 * fraction * fraction),
            y: (controls[1].y - controls[0].y) * (3.0 * complement * complement)
                + (controls[2].y - controls[1].y) * (6.0 * complement * fraction)
                + (controls[3].y - controls[2].y) * (3.0 * fraction * fraction)
        )
    }

    private func cubicSecondDerivativeBound(_ controls: [Point3D]) -> Double {
        let first = Vector3D(
            x: 6.0 * (controls[2].x - 2.0 * controls[1].x + controls[0].x),
            y: 6.0 * (controls[2].y - 2.0 * controls[1].y + controls[0].y),
            z: 6.0 * (controls[2].z - 2.0 * controls[1].z + controls[0].z)
        )
        let second = Vector3D(
            x: 6.0 * (controls[3].x - 2.0 * controls[2].x + controls[1].x),
            y: 6.0 * (controls[3].y - 2.0 * controls[2].y + controls[1].y),
            z: 6.0 * (controls[3].z - 2.0 * controls[2].z + controls[1].z)
        )
        return max(outwardLength(first), outwardLength(second))
    }

    private func cubicParameterDerivativeMagnitudes(_ controls: [Point2D]) -> Point2D {
        Point2D(
            x: (0..<3).map { abs(3.0 * (controls[$0 + 1].x - controls[$0].x)).nextUp }.max() ?? 0.0,
            y: (0..<3).map { abs(3.0 * (controls[$0 + 1].y - controls[$0].y)).nextUp }.max() ?? 0.0
        )
    }

    private func cubicParameterSecondDerivativeMagnitudes(_ controls: [Point2D]) -> Point2D {
        Point2D(
            x: max(
                abs(6.0 * (controls[2].x - 2.0 * controls[1].x + controls[0].x)).nextUp,
                abs(6.0 * (controls[3].x - 2.0 * controls[2].x + controls[1].x)).nextUp
            ),
            y: max(
                abs(6.0 * (controls[2].y - 2.0 * controls[1].y + controls[0].y)).nextUp,
                abs(6.0 * (controls[3].y - 2.0 * controls[2].y + controls[1].y)).nextUp
            )
        )
    }

    private func cubicWeights(fraction: Double) -> [Double] {
        let complement = 1.0 - fraction
        return [
            complement * complement * complement,
            3.0 * complement * complement * fraction,
            3.0 * complement * fraction * fraction,
            fraction * fraction * fraction,
        ]
    }

    private func outwardLength(_ value: Vector3D) -> Double {
        value.length.nextUp
    }

    private func upperProduct(
        _ first: Double,
        _ second: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        let value = (first * second).nextUp
        guard value.isFinite, value >= 0.0 else {
            throw resourceLimit(
                residual: value,
                tolerance: tolerance,
                message: "Cubic surface residual product bound overflowed."
            )
        }
        return value
    }

    private func upperSum(
        _ values: [Double],
        tolerance: ModelingTolerance
    ) throws -> Double {
        var result = 0.0
        for value in values {
            result = (result + value).nextUp
            guard result.isFinite, result >= 0.0 else {
                throw resourceLimit(
                    residual: result,
                    tolerance: tolerance,
                    message: "Cubic surface residual sum bound overflowed."
                )
            }
        }
        return result
    }

    private static func resourceLimit(
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .geometry,
            code: .resourceLimitExceeded,
            residual: residual,
            tolerance: tolerance,
            message: message
        )
    }

    private func resourceLimit(
        residual: Double? = nil,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        Self.resourceLimit(residual: residual, tolerance: tolerance, message: message)
    }
}

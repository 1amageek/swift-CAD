import Foundation
import CADCore

public struct BSplineCurve2D: Codable, Sendable, Hashable {
    public struct DifferentialGeometry: Codable, Sendable, Hashable {
        public var position: Point2D
        public var firstDerivative: Point2D
        public var secondDerivative: Point2D

        public init(position: Point2D, firstDerivative: Point2D, secondDerivative: Point2D) {
            self.position = position
            self.firstDerivative = firstDerivative
            self.secondDerivative = secondDerivative
        }
    }

    public var degree: Int
    public var knots: [Double]
    public var controlPoints: [Point2D]
    public var weights: [Double]

    public init(
        degree: Int,
        knots: [Double],
        controlPoints: [Point2D],
        weights: [Double]? = nil
    ) {
        self.degree = degree
        self.knots = knots
        self.controlPoints = controlPoints
        self.weights = weights ?? Array(repeating: 1.0, count: controlPoints.count)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.degree, .knots, .controlPoints, .weights],
            in: decoder
        )
        let controlPoints = try container.decode([Point2D].self, forKey: .controlPoints)
        self.init(
            degree: try container.decode(Int.self, forKey: .degree),
            knots: try container.decode([Double].self, forKey: .knots),
            controlPoints: controlPoints,
            weights: try container.decode([Double].self, forKey: .weights)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(degree, forKey: .degree)
        try container.encode(knots, forKey: .knots)
        try container.encode(controlPoints, forKey: .controlPoints)
        try container.encode(weights, forKey: .weights)
    }

    public var order: Int {
        degree + 1
    }

    public var controlPointCount: Int {
        controlPoints.count
    }

    public var domain: ParameterDomain {
        guard degree >= 0,
              knots.count > degree + 1 else {
            return .closed(0.0, 0.0)
        }
        return .closed(knots[degree], knots[knots.count - degree - 1])
    }

    public var isRational: Bool {
        weights.contains { abs($0 - 1.0) > 1.0e-12 }
    }

    public func reversed(tolerance: ModelingTolerance) throws -> BSplineCurve2D {
        try Self.projectedFrom3D(
            try lifted3D().reversed(tolerance: tolerance)
        )
    }

    public func insertingKnot(
        _ value: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve2D {
        try Self.projectedFrom3D(
            try lifted3D().insertingKnot(value, tolerance: tolerance)
        )
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve2D {
        try Self.projectedFrom3D(
            try lifted3D().trimmed(
                from: startParameter,
                to: endParameter,
                tolerance: tolerance
            )
        )
    }

    public func settingKnotValue(
        at index: Int,
        to value: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve2D {
        try validate(tolerance: tolerance)
        try tolerance.validate()
        guard value.isFinite else {
            throw GeometryError.invalidCoordinate(value)
        }
        guard isInteriorKnotIndex(index) else {
            throw GeometryError.invalidDistance(Double(index))
        }
        let lowerBound = knots[index - 1]
        let upperBound = knots[index + 1]
        guard value > lowerBound,
              value < upperBound else {
            throw GeometryError.invalidDistance(value)
        }
        var updatedKnots = knots
        updatedKnots[index] = value
        let updatedCurve = BSplineCurve2D(
            degree: degree,
            knots: updatedKnots,
            controlPoints: controlPoints,
            weights: weights
        )
        try updatedCurve.validate(tolerance: tolerance)
        return updatedCurve
    }

    public func settingKnotMultiplicity(
        at index: Int,
        to multiplicity: Int,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve2D {
        try validate(tolerance: tolerance)
        try tolerance.validate()
        guard isInteriorKnotIndex(index) else {
            throw GeometryError.invalidDistance(Double(index))
        }
        let value = knots[index]
        let currentMultiplicity = knotMultiplicity(at: value, tolerance: tolerance)
        guard multiplicity > currentMultiplicity,
              multiplicity <= degree else {
            throw GeometryError.invalidDistance(Double(multiplicity))
        }
        var updatedCurve = self
        for _ in currentMultiplicity..<multiplicity {
            updatedCurve = try updatedCurve.insertingKnot(value, tolerance: tolerance)
        }
        try updatedCurve.validate(tolerance: tolerance)
        return updatedCurve
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard degree >= 1,
              controlPoints.count >= degree + 1,
              controlPoints.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
              weights.count == controlPointCount,
              weights.allSatisfy({ $0.isFinite && $0 > 0.0 }),
              knots.count == controlPointCount + degree + 1,
              knots.allSatisfy(\.isFinite) else {
            throw GeometryError.invalidDistance(0.0)
        }
        for index in 1..<knots.count where knots[index] < knots[index - 1] {
            throw GeometryError.invalidDistance(knots[index] - knots[index - 1])
        }
        let lowerBound = knots[degree]
        let upperBound = knots[knots.count - degree - 1]
        guard upperBound > lowerBound else {
            throw GeometryError.invalidDistance(upperBound - lowerBound)
        }
        var runStart = 0
        while runStart < knots.count {
            var runEnd = runStart + 1
            while runEnd < knots.count, knots[runEnd] == knots[runStart] {
                runEnd += 1
            }
            let value = knots[runStart]
            let maximumMultiplicity = value > lowerBound && value < upperBound
                ? degree
                : degree + 1
            guard runEnd - runStart <= maximumMultiplicity else {
                throw GeometryError.invalidDistance(Double(runEnd - runStart))
            }
            runStart = runEnd
        }
        try domain.validate(tolerance: tolerance)
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point2D {
        try validate(tolerance: tolerance)
        return try pointAssumingValid(at: parameter, tolerance: tolerance)
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        try validate(tolerance: tolerance)
        return try differentialGeometryAssumingValid(
            at: parameter,
            tolerance: tolerance
        )
    }

    func differentialGeometryAssumingValid(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        guard try domain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clamped = BSplineBasis.clampedParameter(
            parameter,
            knots: knots,
            degree: degree
        )
        let basis = BSplineBasis.nonzeroDerivativeValues(
            parameter: clamped,
            degree: degree,
            throughDerivativeOrder: 2,
            knots: knots,
            count: controlPointCount
        )
        let base = weightedPoint(basis: basis[0])
        let first = weightedPoint(basis: basis[1])
        let second = weightedPoint(basis: basis[2])
        guard base.weight.isFinite,
              base.weight > Double.ulpOfOne,
              base.x.isFinite,
              base.y.isFinite else {
            throw GeometryError.invalidDistance(base.weight)
        }
        let position = Point2D(
            x: base.x / base.weight,
            y: base.y / base.weight
        )
        let firstDerivative = Point2D(
            x: (first.x - position.x * first.weight) / base.weight,
            y: (first.y - position.y * first.weight) / base.weight
        )
        let secondDerivative = Point2D(
            x: (
                second.x
                    - position.x * second.weight
                    - 2.0 * firstDerivative.x * first.weight
            ) / base.weight,
            y: (
                second.y
                    - position.y * second.weight
                    - 2.0 * firstDerivative.y * first.weight
            ) / base.weight
        )
        guard position.x.isFinite,
              position.y.isFinite,
              firstDerivative.x.isFinite,
              firstDerivative.y.isFinite,
              secondDerivative.x.isFinite,
              secondDerivative.y.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational two-dimensional B-spline differentiation exceeded the finite numeric range."
            )
        }
        return DifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative
        )
    }

    func pointAssumingValid(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Point2D {
        guard try domain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clamped = BSplineBasis.clampedParameter(
            parameter,
            knots: knots,
            degree: degree
        )
        let weighted = weightedPoint(
            basis: BSplineBasis.nonzeroValues(
                parameter: clamped,
                degree: degree,
                knots: knots,
                count: controlPointCount
            )
        )
        guard weighted.weight.isFinite,
              weighted.weight > Double.ulpOfOne,
              weighted.x.isFinite,
              weighted.y.isFinite else {
            throw GeometryError.invalidDistance(weighted.weight)
        }
        return Point2D(
            x: weighted.x / weighted.weight,
            y: weighted.y / weighted.weight
        )
    }

    private enum CodingKeys: String, CodingKey {
        case degree
        case knots
        case controlPoints
        case weights
    }

    private struct WeightedPoint {
        var x: Double
        var y: Double
        var weight: Double
    }

    private func weightedPoint(
        basis: BSplineBasis.NonzeroValues
    ) -> WeightedPoint {
        var result = WeightedPoint(x: 0.0, y: 0.0, weight: 0.0)
        for (offset, value) in basis.values.enumerated() {
            let index = basis.startIndex + offset
            guard index >= 0, index < controlPointCount else { continue }
            let coefficient = value * weights[index]
            guard coefficient != 0.0 else { continue }
            result.x += controlPoints[index].x * coefficient
            result.y += controlPoints[index].y * coefficient
            result.weight += coefficient
        }
        return result
    }

    private func lifted3D() -> BSplineCurve3D {
        BSplineCurve3D(
            degree: degree,
            knots: knots,
            controlPoints: controlPoints.map {
                Point3D(x: $0.x, y: $0.y, z: 0.0)
            },
            weights: weights
        )
    }

    private static func projectedFrom3D(
        _ curve: BSplineCurve3D
    ) throws -> BSplineCurve2D {
        guard curve.controlPoints.allSatisfy({ $0.z == 0.0 }) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: nil,
                message: "Lifted two-dimensional B-spline operation left the XY plane."
            )
        }
        return BSplineCurve2D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints.map { Point2D(x: $0.x, y: $0.y) },
            weights: curve.weights
        )
    }

    private func knotMultiplicity(
        at value: Double,
        tolerance: ModelingTolerance
    ) -> Int {
        let parameterTolerance = domain.parameterResolution(tolerance: tolerance)
        return knots.filter { abs($0 - value) <= parameterTolerance }.count
    }

    private func isInteriorKnotIndex(_ index: Int) -> Bool {
        let firstInteriorKnotIndex = degree + 1
        let lastInteriorKnotIndex = knots.count - degree - 2
        guard firstInteriorKnotIndex <= lastInteriorKnotIndex,
              (firstInteriorKnotIndex ... lastInteriorKnotIndex).contains(index) else {
            return false
        }
        let lowerBound = knots[degree]
        let upperBound = knots[knots.count - degree - 1]
        let value = knots[index]
        return value > lowerBound && value < upperBound
    }

}

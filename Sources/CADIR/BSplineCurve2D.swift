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
        let controlPoints = try container.decode([Point2D].self, forKey: .controlPoints)
        self.init(
            degree: try container.decode(Int.self, forKey: .degree),
            knots: try container.decode([Double].self, forKey: .knots),
            controlPoints: controlPoints,
            weights: try container.decodeIfPresent([Double].self, forKey: .weights)
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

    public func reversed(tolerance: ModelingTolerance = .standard) throws -> BSplineCurve2D {
        try validate(tolerance: tolerance)
        guard case let .closed(lowerBound, upperBound) = domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        let reversedCurve = BSplineCurve2D(
            degree: degree,
            knots: knots.reversed().map { lowerBound + upperBound - $0 },
            controlPoints: Array(controlPoints.reversed()),
            weights: Array(weights.reversed())
        )
        try reversedCurve.validate(tolerance: tolerance)
        return reversedCurve
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        guard degree >= 1,
              controlPoints.count >= degree + 1 else {
            throw GeometryError.invalidDistance(0.0)
        }
        for point in controlPoints {
            try validate(point)
        }
        try validateWeights()
        try validateKnots()
        try domain.validate(tolerance: tolerance)
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance = .standard) throws -> Point2D {
        try validate(tolerance: tolerance)
        guard try domain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clamped = BSplineBasis.clampedParameter(parameter, knots: knots, degree: degree)
        let basis = BSplineBasis.values(parameter: clamped, degree: degree, knots: knots, count: controlPointCount)
        return try rationalPoint(weightedCurvePoint(basis: basis))
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> DifferentialGeometry {
        try validate(tolerance: tolerance)
        guard try domain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clamped = BSplineBasis.clampedParameter(parameter, knots: knots, degree: degree)
        let basis = BSplineBasis.values(parameter: clamped, degree: degree, knots: knots, count: controlPointCount)
        let firstBasis = BSplineBasis.derivativeValues(
            parameter: clamped,
            degree: degree,
            derivativeOrder: 1,
            knots: knots,
            count: controlPointCount
        )
        let secondBasis = BSplineBasis.derivativeValues(
            parameter: clamped,
            degree: degree,
            derivativeOrder: 2,
            knots: knots,
            count: controlPointCount
        )
        let derivatives = try rationalDerivatives(
            basis: basis,
            firstBasis: firstBasis,
            secondBasis: secondBasis
        )
        return DifferentialGeometry(
            position: derivatives.position,
            firstDerivative: derivatives.first,
            secondDerivative: derivatives.second
        )
    }

    private enum CodingKeys: String, CodingKey {
        case degree
        case knots
        case controlPoints
        case weights
    }

    private struct WeightedPoint {
        var point: Point2D
        var weight: Double
    }

    private struct RationalDerivatives {
        var position: Point2D
        var first: Point2D
        var second: Point2D
    }

    private func validate(_ point: Point2D) throws {
        guard point.x.isFinite else {
            throw GeometryError.invalidCoordinate(point.x)
        }
        guard point.y.isFinite else {
            throw GeometryError.invalidCoordinate(point.y)
        }
    }

    private func validateWeights() throws {
        guard weights.count == controlPointCount else {
            throw GeometryError.invalidDistance(Double(weights.count))
        }
        for weight in weights {
            guard weight.isFinite else {
                throw GeometryError.invalidCoordinate(weight)
            }
            guard weight > 0.0 else {
                throw GeometryError.invalidDistance(weight)
            }
        }
    }

    private func validateKnots() throws {
        guard knots.count == controlPointCount + degree + 1 else {
            throw GeometryError.invalidDistance(Double(knots.count))
        }
        for knot in knots {
            guard knot.isFinite else {
                throw GeometryError.invalidCoordinate(knot)
            }
        }
        for index in 1..<knots.count {
            guard knots[index] >= knots[index - 1] else {
                throw GeometryError.invalidDistance(knots[index] - knots[index - 1])
            }
        }
        let lowerBound = knots[degree]
        let upperBound = knots[knots.count - degree - 1]
        guard upperBound > lowerBound else {
            throw GeometryError.invalidDistance(upperBound - lowerBound)
        }
    }

    private func rationalDerivatives(
        basis: [Double],
        firstBasis: [Double],
        secondBasis: [Double]
    ) throws -> RationalDerivatives {
        let base = weightedCurvePoint(basis: basis)
        let first = weightedCurvePoint(basis: firstBasis)
        let second = weightedCurvePoint(basis: secondBasis)
        let position = try rationalPoint(base)
        let firstDerivative = (first.point - position * first.weight) / base.weight
        let secondDerivative = (
            second.point -
                position * second.weight -
                firstDerivative * (2.0 * first.weight)
        ) / base.weight
        return RationalDerivatives(
            position: position,
            first: firstDerivative,
            second: secondDerivative
        )
    }

    private func rationalPoint(_ weighted: WeightedPoint) throws -> Point2D {
        guard weighted.weight.isFinite,
              weighted.weight > Double.ulpOfOne,
              weighted.point.x.isFinite,
              weighted.point.y.isFinite else {
            throw GeometryError.invalidDistance(weighted.weight)
        }
        return weighted.point / weighted.weight
    }

    private func weightedCurvePoint(basis: [Double]) -> WeightedPoint {
        var point = Point2D(x: 0.0, y: 0.0)
        var weightSum = 0.0
        for index in 0..<controlPointCount {
            let basisWeight = basis[index] * weights[index]
            guard basisWeight != 0.0 else {
                continue
            }
            point = point + controlPoints[index] * basisWeight
            weightSum += basisWeight
        }
        return WeightedPoint(point: point, weight: weightSum)
    }
}

private func + (lhs: Point2D, rhs: Point2D) -> Point2D {
    Point2D(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
}

private func - (lhs: Point2D, rhs: Point2D) -> Point2D {
    Point2D(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
}

private func * (lhs: Point2D, rhs: Double) -> Point2D {
    Point2D(x: lhs.x * rhs, y: lhs.y * rhs)
}

private func / (lhs: Point2D, rhs: Double) -> Point2D {
    Point2D(x: lhs.x / rhs, y: lhs.y / rhs)
}

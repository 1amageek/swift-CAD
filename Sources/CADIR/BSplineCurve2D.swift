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

    public func insertingKnot(
        _ value: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> BSplineCurve2D {
        try validate(tolerance: tolerance)
        try tolerance.validate()
        guard value.isFinite else {
            throw GeometryError.invalidCoordinate(value)
        }
        guard case let .closed(lowerBound, upperBound) = domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        let insertionValue = canonicalKnotValue(value, tolerance: tolerance)
        guard insertionValue > lowerBound + tolerance.distance,
              insertionValue < upperBound - tolerance.distance else {
            throw GeometryError.invalidDistance(insertionValue)
        }
        let multiplicity = knotMultiplicity(
            at: insertionValue,
            tolerance: tolerance
        )
        guard multiplicity < degree else {
            throw GeometryError.invalidDistance(insertionValue)
        }

        let span = knotSpan(containing: insertionValue)
        let lastControlPointIndex = controlPointCount - 1
        var updatedWeightedPoints = Array(
            repeating: HomogeneousPoint.zero,
            count: controlPointCount + 1
        )
        let weightedPoints = homogeneousControlPoints()

        let unchangedPrefixEnd = span - degree
        if unchangedPrefixEnd >= 0 {
            for index in 0...unchangedPrefixEnd {
                updatedWeightedPoints[index] = weightedPoints[index]
            }
        }

        let unchangedSuffixStart = span - multiplicity + 1
        if unchangedSuffixStart <= lastControlPointIndex + 1 {
            for index in unchangedSuffixStart...(lastControlPointIndex + 1) {
                updatedWeightedPoints[index] = weightedPoints[index - 1]
            }
        }

        let blendedStart = span - degree + 1
        let blendedEnd = span - multiplicity
        if blendedStart <= blendedEnd {
            for index in blendedStart...blendedEnd {
                let denominator = knots[index + degree] - knots[index]
                guard denominator > Double.ulpOfOne else {
                    throw GeometryError.invalidDistance(denominator)
                }
                let alpha = (insertionValue - knots[index]) / denominator
                updatedWeightedPoints[index] = weightedPoints[index]
                    .scaled(by: alpha)
                    .adding(weightedPoints[index - 1].scaled(by: 1.0 - alpha))
            }
        }

        let updatedCurve = try BSplineCurve2D(
            degree: degree,
            knots: Array(knots.prefix(span + 1))
                + [insertionValue]
                + Array(knots.suffix(from: span + 1)),
            controlPoints: updatedWeightedPoints.map { try $0.point() },
            weights: updatedWeightedPoints.map(\.weight)
        )
        try updatedCurve.validate(tolerance: tolerance)
        return updatedCurve
    }

    public func settingKnotValue(
        at index: Int,
        to value: Double,
        tolerance: ModelingTolerance = .standard
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
        tolerance: ModelingTolerance = .standard
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

    private struct HomogeneousPoint {
        static let zero = HomogeneousPoint(x: 0.0, y: 0.0, weight: 0.0)

        var x: Double
        var y: Double
        var weight: Double

        func adding(_ other: HomogeneousPoint) -> HomogeneousPoint {
            HomogeneousPoint(
                x: x + other.x,
                y: y + other.y,
                weight: weight + other.weight
            )
        }

        func scaled(by scalar: Double) -> HomogeneousPoint {
            HomogeneousPoint(
                x: x * scalar,
                y: y * scalar,
                weight: weight * scalar
            )
        }

        func point() throws -> Point2D {
            guard weight.isFinite,
                  weight > Double.ulpOfOne,
                  x.isFinite,
                  y.isFinite else {
                throw GeometryError.invalidDistance(weight)
            }
            return Point2D(x: x / weight, y: y / weight)
        }
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

    private func homogeneousControlPoints() -> [HomogeneousPoint] {
        controlPoints.indices.map { index in
            let weight = weights[index]
            let point = controlPoints[index]
            return HomogeneousPoint(
                x: point.x * weight,
                y: point.y * weight,
                weight: weight
            )
        }
    }

    private func canonicalKnotValue(
        _ value: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        for knot in knots where abs(knot - value) <= tolerance.distance {
            return knot
        }
        return value
    }

    private func knotMultiplicity(
        at value: Double,
        tolerance: ModelingTolerance
    ) -> Int {
        knots.filter { abs($0 - value) <= tolerance.distance }.count
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

    private func knotSpan(containing value: Double) -> Int {
        let lastControlPointIndex = controlPointCount - 1
        if value >= knots[lastControlPointIndex + 1] {
            return lastControlPointIndex
        }
        var lower = degree
        var upper = lastControlPointIndex + 1
        var middle = (lower + upper) / 2
        while value < knots[middle] || value >= knots[middle + 1] {
            if value < knots[middle] {
                upper = middle
            } else {
                lower = middle
            }
            middle = (lower + upper) / 2
        }
        return middle
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

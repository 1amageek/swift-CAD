import Foundation
import CADCore

public struct BSplineCurve3D: Codable, Sendable, Hashable {
    public struct DifferentialGeometry: Codable, Sendable, Hashable {
        public var position: Point3D
        public var firstDerivative: Vector3D
        public var secondDerivative: Vector3D
        public var tangent: Vector3D
        public var curvatureVector: Vector3D
        public var curvature: Double

        public init(
            position: Point3D,
            firstDerivative: Vector3D,
            secondDerivative: Vector3D,
            tangent: Vector3D,
            curvatureVector: Vector3D,
            curvature: Double
        ) {
            self.position = position
            self.firstDerivative = firstDerivative
            self.secondDerivative = secondDerivative
            self.tangent = tangent
            self.curvatureVector = curvatureVector
            self.curvature = curvature
        }
    }

    public var degree: Int
    public var knots: [Double]
    public var controlPoints: [Point3D]
    public var weights: [Double]

    public init(
        degree: Int,
        knots: [Double],
        controlPoints: [Point3D],
        weights: [Double]? = nil
    ) {
        self.degree = degree
        self.knots = knots
        self.controlPoints = controlPoints
        self.weights = weights ?? Array(repeating: 1.0, count: controlPoints.count)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let controlPoints = try container.decode([Point3D].self, forKey: .controlPoints)
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
        guard knots.count > degree + 1 else {
            return .closed(0.0, 0.0)
        }
        return .closed(knots[degree], knots[knots.count - degree - 1])
    }

    public var isRational: Bool {
        weights.contains { abs($0 - 1.0) > 1.0e-12 }
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        guard degree >= 1,
              controlPoints.count >= degree + 1 else {
            throw GeometryError.invalidDistance(0.0)
        }
        for point in controlPoints {
            try point.validate()
        }
        try validateWeights()
        try validateKnots()
        try domain.validate(tolerance: tolerance)
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance = .standard) throws -> Point3D {
        try validate(tolerance: tolerance)
        guard try domain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clamped = BSplineBasis.clampedParameter(parameter, knots: knots, degree: degree)
        let basis = BSplineBasis.values(parameter: clamped, degree: degree, knots: knots, count: controlPointCount)
        let position = try rationalPoint(basis: basis)
        return Point3D(x: position.x, y: position.y, z: position.z)
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
        let tangent = try derivatives.first.normalized(tolerance: tolerance.distance)
        let speed = derivatives.first.length
        let tangentialAcceleration = tangent * derivatives.second.dot(tangent)
        let curvatureVector = (derivatives.second - tangentialAcceleration) / (speed * speed)
        return DifferentialGeometry(
            position: derivatives.position,
            firstDerivative: derivatives.first,
            secondDerivative: derivatives.second,
            tangent: tangent,
            curvatureVector: curvatureVector,
            curvature: curvatureVector.length
        )
    }

    private enum CodingKeys: String, CodingKey {
        case degree
        case knots
        case controlPoints
        case weights
    }

    private struct WeightedVector {
        var point: Vector3D
        var weight: Double
    }

    private struct RationalDerivatives {
        var position: Point3D
        var first: Vector3D
        var second: Vector3D
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

    private func rationalPoint(basis: [Double]) throws -> Vector3D {
        try rationalVector(weightedCurveVector(basis: basis))
    }

    private func rationalDerivatives(
        basis: [Double],
        firstBasis: [Double],
        secondBasis: [Double]
    ) throws -> RationalDerivatives {
        let base = weightedCurveVector(basis: basis)
        let first = weightedCurveVector(basis: firstBasis)
        let second = weightedCurveVector(basis: secondBasis)
        let positionVector = try rationalVector(base)
        let firstDerivative = (first.point - positionVector * first.weight) / base.weight
        let secondDerivative = (
            second.point -
                positionVector * second.weight -
                firstDerivative * (2.0 * first.weight)
        ) / base.weight
        return RationalDerivatives(
            position: Point3D(x: positionVector.x, y: positionVector.y, z: positionVector.z),
            first: firstDerivative,
            second: secondDerivative
        )
    }

    private func rationalVector(_ weighted: WeightedVector) throws -> Vector3D {
        guard weighted.weight.isFinite,
              weighted.weight > Double.ulpOfOne,
              weighted.point.isFinite else {
            throw GeometryError.invalidDistance(weighted.weight)
        }
        return weighted.point / weighted.weight
    }

    private func weightedCurveVector(basis: [Double]) -> WeightedVector {
        var point = Vector3D.zero
        var weightSum = 0.0
        for index in 0..<controlPointCount {
            let basisWeight = basis[index] * weights[index]
            guard basisWeight != 0.0 else {
                continue
            }
            point = point + vector(from: controlPoints[index]) * basisWeight
            weightSum += basisWeight
        }
        return WeightedVector(point: point, weight: weightSum)
    }

    private func vector(from point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }
}

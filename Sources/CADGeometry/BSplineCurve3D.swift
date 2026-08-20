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
        try container.validateOnlyExpectedKeys(
            [.degree, .knots, .controlPoints, .weights],
            in: decoder
        )
        let controlPoints = try container.decode([Point3D].self, forKey: .controlPoints)
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
        guard knots.count > degree + 1 else {
            return .closed(0.0, 0.0)
        }
        return .closed(knots[degree], knots[knots.count - degree - 1])
    }

    public var isRational: Bool {
        weights.contains { abs($0 - 1.0) > 1.0e-12 }
    }

    public func reversed(tolerance: ModelingTolerance) throws -> BSplineCurve3D {
        try validate(tolerance: tolerance)
        guard case let .closed(lowerBound, upperBound) = domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        let reversedCurve = BSplineCurve3D(
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
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        try validate(tolerance: tolerance)
        guard value.isFinite else {
            throw GeometryError.invalidCoordinate(value)
        }
        guard case let .closed(lowerBound, upperBound) = domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        let parameterTolerance = domain.parameterResolution(tolerance: tolerance)
        let insertionValue = canonicalKnotValue(value, tolerance: tolerance)
        guard insertionValue > lowerBound + parameterTolerance,
              insertionValue < upperBound - parameterTolerance else {
            throw GeometryError.invalidDistance(insertionValue)
        }
        let multiplicity = knotMultiplicity(at: insertionValue, tolerance: tolerance)
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

        let updatedCurve = try BSplineCurve3D(
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

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        try validate(tolerance: tolerance)
        let start = canonicalKnotValue(startParameter, tolerance: tolerance)
        let end = canonicalKnotValue(endParameter, tolerance: tolerance)
        if case let .closed(lower, upper) = domain,
           start == lower,
           end == upper {
            return self
        }
        return try BSplineCurvePatchAssembler().trimmedCurve(
            source: self,
            lower: start,
            upper: end,
            tolerance: tolerance
        )
    }

    public func validate(tolerance: ModelingTolerance) throws {
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

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try validate(tolerance: tolerance)
        return try pointAssumingValid(at: parameter, tolerance: tolerance)
    }

    func pointAssumingValid(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        guard try domain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clamped = BSplineBasis.clampedParameter(parameter, knots: knots, degree: degree)
        let basis = BSplineBasis.nonzeroValues(
            parameter: clamped,
            degree: degree,
            knots: knots,
            count: controlPointCount
        )
        let position = try rationalPoint(basis: basis)
        return Point3D(x: position.x, y: position.y, z: position.z)
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
        let clamped = BSplineBasis.clampedParameter(parameter, knots: knots, degree: degree)
        let basis = BSplineBasis.nonzeroDerivativeValues(
            parameter: clamped,
            degree: degree,
            throughDerivativeOrder: 2,
            knots: knots,
            count: controlPointCount
        )
        let derivatives = try rationalDerivatives(
            basis: basis[0],
            firstBasis: basis[1],
            secondBasis: basis[2]
        )
        guard derivatives.first.isFinite,
              derivatives.second.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational B-spline curve differentiation exceeded the finite numeric range."
            )
        }
        let speed = derivatives.first.length
        guard speed.isFinite,
              speed > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                residual: speed,
                tolerance: tolerance,
                message: "Rational B-spline curve differential geometry is singular at the requested parameter."
            )
        }
        let tangent = derivatives.first / speed
        let tangentialAcceleration = tangent * derivatives.second.dot(tangent)
        let curvatureVector = (derivatives.second - tangentialAcceleration) / (speed * speed)
        guard tangent.isFinite,
              curvatureVector.isFinite,
              curvatureVector.length.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational B-spline curve curvature exceeded the finite numeric range."
            )
        }
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

    private struct HomogeneousPoint {
        static let zero = HomogeneousPoint(x: 0.0, y: 0.0, z: 0.0, weight: 0.0)

        var x: Double
        var y: Double
        var z: Double
        var weight: Double

        func adding(_ other: HomogeneousPoint) -> HomogeneousPoint {
            HomogeneousPoint(
                x: x + other.x,
                y: y + other.y,
                z: z + other.z,
                weight: weight + other.weight
            )
        }

        func scaled(by scalar: Double) -> HomogeneousPoint {
            HomogeneousPoint(
                x: x * scalar,
                y: y * scalar,
                z: z * scalar,
                weight: weight * scalar
            )
        }

        func point() throws -> Point3D {
            guard weight.isFinite,
                  weight > Double.ulpOfOne,
                  x.isFinite,
                  y.isFinite,
                  z.isFinite else {
                throw GeometryError.invalidDistance(weight)
            }
            return Point3D(x: x / weight, y: y / weight, z: z / weight)
        }
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
        try validateKnotMultiplicities(
            lowerBound: lowerBound,
            upperBound: upperBound
        )
    }

    private func validateKnotMultiplicities(
        lowerBound: Double,
        upperBound: Double
    ) throws {
        var runStart = 0
        while runStart < knots.count {
            var runEnd = runStart + 1
            while runEnd < knots.count, knots[runEnd] == knots[runStart] {
                runEnd += 1
            }
            let multiplicity = runEnd - runStart
            let value = knots[runStart]
            let maximumMultiplicity = value > lowerBound && value < upperBound
                ? degree
                : degree + 1
            guard multiplicity <= maximumMultiplicity else {
                throw GeometryError.invalidDistance(Double(multiplicity))
            }
            runStart = runEnd
        }
    }

    private func rationalPoint(
        basis: BSplineBasis.NonzeroValues
    ) throws -> Vector3D {
        try rationalVector(weightedCurveVector(basis: basis))
    }

    private func rationalDerivatives(
        basis: BSplineBasis.NonzeroValues,
        firstBasis: BSplineBasis.NonzeroValues,
        secondBasis: BSplineBasis.NonzeroValues
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

    private func weightedCurveVector(
        basis: BSplineBasis.NonzeroValues
    ) -> WeightedVector {
        var point = Vector3D.zero
        var weightSum = 0.0
        for (offset, value) in basis.values.enumerated() {
            let index = basis.startIndex + offset
            guard index >= 0, index < controlPointCount else { continue }
            let basisWeight = value * weights[index]
            guard basisWeight != 0.0 else {
                continue
            }
            point = point + vector(from: controlPoints[index]) * basisWeight
            weightSum += basisWeight
        }
        return WeightedVector(point: point, weight: weightSum)
    }

    private func homogeneousControlPoints() -> [HomogeneousPoint] {
        controlPoints.indices.map { index in
            let point = controlPoints[index]
            let weight = weights[index]
            return HomogeneousPoint(
                x: point.x * weight,
                y: point.y * weight,
                z: point.z * weight,
                weight: weight
            )
        }
    }

    private func canonicalKnotValue(
        _ value: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        let parameterTolerance = domain.parameterResolution(tolerance: tolerance)
        for knot in knots where abs(knot - value) <= parameterTolerance {
            return knot
        }
        return value
    }

    private func knotMultiplicity(
        at value: Double,
        tolerance: ModelingTolerance
    ) -> Int {
        let parameterTolerance = domain.parameterResolution(tolerance: tolerance)
        return knots.filter { abs($0 - value) <= parameterTolerance }.count
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

    private func vector(from point: Point3D) -> Vector3D {
        Vector3D(x: point.x, y: point.y, z: point.z)
    }
}

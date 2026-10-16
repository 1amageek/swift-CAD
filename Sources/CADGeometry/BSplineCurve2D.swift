#if !hasFeature(Embedded)
import Foundation
#elseif canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADGeometry numeric algorithms require the target C math module.")
#endif
import CADCore

public struct BSplineCurve2D: Sendable, Hashable {
    public struct DifferentialGeometry: Sendable, Hashable {
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

#if !hasFeature(Embedded)
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
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(degree, forKey: .degree)
        try container.encode(knots, forKey: .knots)
        try container.encode(controlPoints, forKey: .controlPoints)
        try container.encode(weights, forKey: .weights)
    }
#endif

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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try reversed(tolerance: tolerance, using: &execution)
    }

    public func insertingKnot(_ value: Double, tolerance: ModelingTolerance) throws -> BSplineCurve2D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try insertingKnot(value, tolerance: tolerance, using: &execution)
    }

    public func trimmed(from startParameter: Double, to endParameter: Double, tolerance: ModelingTolerance) throws -> BSplineCurve2D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try trimmed(from: startParameter, to: endParameter, tolerance: tolerance, using: &execution)
    }

    public func trimmedAcrossSeam(from startParameter: Double, to endParameter: Double, tolerance: ModelingTolerance) throws -> BSplineCurve2D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try trimmedAcrossSeam(from: startParameter, to: endParameter, tolerance: tolerance, using: &execution)
    }

    func shifted(by offset: Double) throws -> BSplineCurve2D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try shifted(by: offset, using: &execution)
    }

    public func reversed<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance, using execution: inout A) throws -> BSplineCurve2D {
        try execution.checkpoint(); try execution.consumeWork( 1)
        return try Self.projectedFrom3D(
            try lifted3D(using: &execution).reversed(tolerance: tolerance, using: &execution), using: &execution
        )
    }

    public func insertingKnot<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineCurve2D {
        try execution.checkpoint(); try execution.consumeWork( 1)
        return try Self.projectedFrom3D(
            try lifted3D(using: &execution).insertingKnot(value, tolerance: tolerance, using: &execution), using: &execution
        )
    }

    public func trimmed<A: ExactScalarAdmission & ~Copyable>(
        from startParameter: Double,
        to endParameter: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineCurve2D {
        try execution.checkpoint(); try execution.consumeWork( 1)
        return try Self.projectedFrom3D(
            try lifted3D(using: &execution).trimmed(
                from: startParameter,
                to: endParameter,
                tolerance: tolerance, using: &execution
            ), using: &execution
        )
    }

    /// The stretch from `startParameter` to `endParameter` of a closed curve read as periodic:
    /// a span running past its domain's end carries on from its start, the two pieces joined at
    /// the seam (C0, the second's weights scaled to meet the first's), the parameters kept as asked.
    /// A span inside the domain is `trimmed(from:to:, using: &execution)`.
    public func trimmedAcrossSeam<A: ExactScalarAdmission & ~Copyable>(
        from startParameter: Double,
        to endParameter: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineCurve2D {
        try execution.checkpoint(); try execution.consumeWork( 1)
        guard case let .closed(lower, upper) = domain, upper > lower, endParameter > startParameter else {
            return try trimmed(from: startParameter, to: endParameter, tolerance: tolerance, using: &execution)
        }
        let period = upper - lower
        let turns = ((startParameter - lower) / period).rounded(.down)
        let (start, end) = (startParameter - turns * period, endParameter - turns * period)
        let slack = max(tolerance.angle, tolerance.distance)
        guard end > upper + slack else {
            return try trimmed(from: max(start, lower), to: min(end, upper), tolerance: tolerance, using: &execution).shifted(by: turns * period, using: &execution)
        }
        guard end - start <= period + slack,
              let a = Optional(try point(at: lower, tolerance: tolerance, using: &execution)), let b = Optional(try point(at: upper, tolerance: tolerance, using: &execution)),
              ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot() <= tolerance.distance else {
            throw GeometryError.invalidDistance(endParameter - startParameter)
        }
        let first = try trimmed(from: start, to: upper, tolerance: tolerance, using: &execution)
        let second = try trimmed(from: lower, to: end - period, tolerance: tolerance, using: &execution).shifted(by: period, using: &execution)
        guard first.degree == second.degree, let lastWeight = first.weights.last, let firstWeight = second.weights.first, firstWeight != 0 else {
            throw GeometryError.invalidDistance(endParameter - startParameter)
        }
        let scale = lastWeight / firstWeight
        let knotCounts = first.knots.dropLast().count.addingReportingOverflow(second.knots.dropFirst(second.degree + 1).count)
        guard !knotCounts.overflow else { throw ExactScalarFailure.countOverflow }
        let knotCount = knotCounts.partialValue
        let pointCount = first.controlPoints.count.addingReportingOverflow(second.controlPoints.count - 1)
        let weightCount = first.weights.count.addingReportingOverflow(second.weights.count - 1)
        guard !pointCount.overflow, !weightCount.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: knotCount, of: Double.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: pointCount.partialValue, of: Point2D.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: weightCount.partialValue, of: Double.self))
        var joinedKnots: [Double] = []; joinedKnots.reserveCapacity(knotCount)
        var joinedPoints: [Point2D] = []; joinedPoints.reserveCapacity(pointCount.partialValue)
        var joinedWeights: [Double] = []; joinedWeights.reserveCapacity(weightCount.partialValue)
        for knot in first.knots.dropLast() { try execution.checkpoint(); try execution.consumeWork( 1); joinedKnots.append(knot) }
        for knot in second.knots.dropFirst(second.degree + 1) { try execution.checkpoint(); try execution.consumeWork( 1); joinedKnots.append(knot) }
        for point in first.controlPoints { try execution.checkpoint(); try execution.consumeWork( 1); joinedPoints.append(point) }
        for point in second.controlPoints.dropFirst() { try execution.checkpoint(); try execution.consumeWork( 1); joinedPoints.append(point) }
        for weight in first.weights { try execution.checkpoint(); try execution.consumeWork( 1); joinedWeights.append(weight) }
        for weight in second.weights.dropFirst() { try execution.checkpoint(); try execution.consumeWork( 1); joinedWeights.append(weight * scale) }
        let joined = BSplineCurve2D(degree: first.degree, knots: joinedKnots,
            controlPoints: joinedPoints, weights: joinedWeights)
        return try joined.shifted(by: turns * period, using: &execution)
    }

    /// The curve with its parameters moved by `offset`.
    func shifted<A: ExactScalarAdmission & ~Copyable>(by offset: Double, using execution: inout A) throws -> BSplineCurve2D {
        try execution.checkpoint(); try execution.consumeWork( 1)
        guard offset != 0 else { return self }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: knots.count, of: Double.self))
        let shiftedKnots = try knots.map { knot in
            try execution.checkpoint(); try execution.consumeWork( 1)
            return knot + offset
        }
        return BSplineCurve2D(degree: degree, knots: shiftedKnots, controlPoints: controlPoints, weights: weights)
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
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try validate(tolerance: tolerance, using: &execution)
    }

    package func validate<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance, using execution: inout A) throws {
        try tolerance.validate(); try execution.consumeWork(1)
        guard degree >= 1, controlPoints.count >= degree + 1,
              weights.count == controlPointCount, knots.count == controlPointCount + degree + 1 else {
            throw GeometryError.invalidDistance(0)
        }
        for point in controlPoints {
            try execution.consumeWork(1)
            guard point.x.isFinite, point.y.isFinite else { throw GeometryError.invalidDistance(0) }
        }
        for weight in weights {
            try execution.consumeWork(1)
            guard weight.isFinite, weight > 0 else { throw GeometryError.invalidDistance(0) }
        }
        for index in knots.indices {
            try execution.consumeWork(1)
            guard knots[index].isFinite else { throw GeometryError.invalidDistance(0) }
            if index > 0, knots[index] < knots[index - 1] {
                throw GeometryError.invalidDistance(knots[index] - knots[index - 1])
            }
        }
        let lowerBound = knots[degree], upperBound = knots[knots.count - degree - 1]
        guard upperBound > lowerBound else { throw GeometryError.invalidDistance(upperBound - lowerBound) }
        var runStart = 0
        while runStart < knots.count {
            try execution.consumeWork(1)
            var runEnd = runStart + 1
            while runEnd < knots.count, knots[runEnd] == knots[runStart] {
                try execution.consumeWork(1); runEnd += 1
            }
            let value = knots[runStart]
            let maximumMultiplicity = value > lowerBound && value < upperBound ? degree : degree + 1
            guard runEnd - runStart <= maximumMultiplicity else {
                throw GeometryError.invalidDistance(Double(runEnd - runStart))
            }
            runStart = runEnd
        }
        try domain.validate(tolerance: tolerance)
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point2D {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try point(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try differentialGeometry(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func point<A: ExactScalarAdmission & ~Copyable>(at parameter: Double, tolerance: ModelingTolerance, using execution: inout A) throws -> Point2D {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        return try pointAssumingValid(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func differentialGeometry<A: ExactScalarAdmission & ~Copyable>(
        at parameter: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> DifferentialGeometry {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        return try differentialGeometryAssumingValid(
            at: parameter,
            tolerance: tolerance, using: &execution
        )
    }

    func differentialGeometryAssumingValid<A: ExactScalarAdmission & ~Copyable>(
        at parameter: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> DifferentialGeometry {
        try execution.consumeWork(1)
        guard try domain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clamped = BSplineBasis.clampedParameter(
            parameter,
            knots: knots,
            degree: degree
        )
        let basis = try BSplineBasis.nonzeroDerivativeValues(
            parameter: clamped,
            degree: degree,
            throughDerivativeOrder: 2,
            knots: knots,
            count: controlPointCount, using: &execution
        )
        let base = try weightedPoint(basis: basis[0], using: &execution)
        let first = try weightedPoint(basis: basis[1], using: &execution)
        let second = try weightedPoint(basis: basis[2], using: &execution)
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

    func pointAssumingValid<A: ExactScalarAdmission & ~Copyable>(
        at parameter: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Point2D {
        try execution.consumeWork(1)
        guard try domain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clamped = BSplineBasis.clampedParameter(
            parameter,
            knots: knots,
            degree: degree
        )
        let weighted = try weightedPoint(
            basis: try BSplineBasis.nonzeroValues(
                parameter: clamped,
                degree: degree,
                knots: knots,
                count: controlPointCount, using: &execution
            ), using: &execution
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

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case degree
        case knots
        case controlPoints
        case weights
    }
#endif

    private struct WeightedPoint {
        var x: Double
        var y: Double
        var weight: Double
    }

    private func weightedPoint<A: ExactScalarAdmission & ~Copyable>(
        basis: BSplineBasis.NonzeroValues, using execution: inout A
    ) throws -> WeightedPoint {
        try execution.consumeWork(1)
        var result = WeightedPoint(x: 0.0, y: 0.0, weight: 0.0)
        for (offset, value) in basis.values.enumerated() {
            try execution.consumeWork(1)
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

    private func lifted3D<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> BSplineCurve3D {
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlPoints.count, of: Point3D.self))
        let lifted = try controlPoints.map { point in
            try execution.checkpoint(); try execution.consumeWork( 1)
            return Point3D(x: point.x, y: point.y, z: 0)
        }
        return BSplineCurve3D(degree: degree, knots: knots, controlPoints: lifted, weights: weights)
    }

    private static func projectedFrom3D<A: ExactScalarAdmission & ~Copyable>(
        _ curve: BSplineCurve3D, using execution: inout A
    ) throws -> BSplineCurve2D {
        for point in curve.controlPoints {
            try execution.checkpoint(); try execution.consumeWork( 1)
            guard point.z == 0 else {
                throw KernelError(phase: .geometry, code: .intersectionFailure, tolerance: nil,
                    message: "Lifted two-dimensional B-spline operation left the XY plane.")
            }
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: curve.controlPoints.count, of: Point2D.self))
        let projected = try curve.controlPoints.map { point in
            try execution.checkpoint(); try execution.consumeWork( 1)
            return Point2D(x: point.x, y: point.y)
        }
        return BSplineCurve2D(degree: curve.degree, knots: curve.knots,
            controlPoints: projected, weights: curve.weights)
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

#if !hasFeature(Embedded)
extension BSplineCurve2D: Codable {}
extension BSplineCurve2D.DifferentialGeometry: Codable {}
#endif

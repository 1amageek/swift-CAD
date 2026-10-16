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

public struct BSplineCurve3D: Sendable, Hashable {
    public struct DifferentialGeometry: Sendable, Hashable {
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
    public var isPeriodic: Bool
    /// The chosen interval of periodic representatives; the curve function is unchanged.
    public var periodicOrigin: Double?

    public init(
        degree: Int,
        knots: [Double],
        controlPoints: [Point3D],
        weights: [Double]? = nil,
        isPeriodic: Bool = false,
        periodicOrigin: Double? = nil
    ) {
        self.degree = degree
        self.knots = knots
        self.controlPoints = controlPoints
        self.weights = weights ?? Array(repeating: 1.0, count: controlPoints.count)
        self.isPeriodic = isPeriodic
        self.periodicOrigin = periodicOrigin
    }

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.degree, .knots, .controlPoints, .weights, .isPeriodic, .periodicOrigin],
            in: decoder
        )
        let controlPoints = try container.decode([Point3D].self, forKey: .controlPoints)
        self.init(
            degree: try container.decode(Int.self, forKey: .degree),
            knots: try container.decode([Double].self, forKey: .knots),
            controlPoints: controlPoints,
            weights: try container.decode([Double].self, forKey: .weights),
            isPeriodic: try container.decode(Bool.self, forKey: .isPeriodic),
            periodicOrigin: try container.decodeIfPresent(Double.self, forKey: .periodicOrigin)
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
        try container.encode(isPeriodic, forKey: .isPeriodic)
        try container.encodeIfPresent(periodicOrigin, forKey: .periodicOrigin)
    }
#endif

    public var order: Int {
        degree + 1
    }

    public var controlPointCount: Int {
        controlPoints.count
    }

    public var domain: ParameterDomain {
        guard degree >= 0, degree < knots.count - 1 else {
            return .closed(0.0, 0.0)
        }
        if isPeriodic {
            return .periodic(period: knots[knots.count - degree - 1] - knots[degree])
        }
        return .closed(knots[degree], knots[knots.count - degree - 1])
    }

    public var isRational: Bool {
        weights.contains { abs($0 - 1.0) > 1.0e-12 }
    }

    public func reversed(tolerance: ModelingTolerance) throws -> BSplineCurve3D {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try reversed(tolerance: tolerance, using: &execution)
    }

    public func insertingKnot(
        _ value: Double,
        expansionOptions: PeriodicBSplineExpansionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try insertingKnot(value, expansionOptions: expansionOptions, tolerance: tolerance, using: &execution)
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        expansionOptions: PeriodicBSplineExpansionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try trimmed(from: startParameter, to: endParameter, expansionOptions: expansionOptions, tolerance: tolerance, using: &execution)
    }

    public func reversed<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance, using execution: inout A) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        guard case let .closed(lowerBound, upperBound) = fundamentalDomain else {
            throw GeometryError.invalidDistance(0.0)
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: knots.count, of: Double.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlPoints.count, of: Point3D.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: weights.count, of: Double.self))
        for _ in controlPoints { try execution.consumeWork(1) }
        for _ in weights { try execution.consumeWork(1) }
        let reversedCurve = BSplineCurve3D(
            degree: degree,
            knots: try knots.reversed().map { try execution.consumeWork(1); return lowerBound + upperBound - $0 },
            controlPoints: Array(try controlPoints.reversed()),
            weights: Array(try weights.reversed()),
            isPeriodic: isPeriodic,
            periodicOrigin: periodicOrigin
        )
        try reversedCurve.validate(tolerance: tolerance, using: &execution)
        return reversedCurve
    }

    public func insertingKnot<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        expansionOptions: PeriodicBSplineExpansionOptions = .init(),
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        if isPeriodic {
            return try periodicRefinement(at: value, options: expansionOptions, tolerance: tolerance, using: &execution)
        }
        guard value.isFinite else {
            throw GeometryError.invalidCoordinate(value)
        }
        guard case let .closed(lowerBound, upperBound) = domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        let parameterTolerance = domain.parameterResolution(tolerance: tolerance)
        let insertionValue = try canonicalKnotValue(value, tolerance: tolerance, using: &execution)
        guard insertionValue > lowerBound + parameterTolerance,
              insertionValue < upperBound - parameterTolerance else {
            throw GeometryError.invalidDistance(insertionValue)
        }
        let multiplicity = try knotMultiplicity(at: insertionValue, tolerance: tolerance, using: &execution)
        guard multiplicity < degree else {
            throw GeometryError.invalidDistance(insertionValue)
        }

        return try insertingInteriorKnot(insertionValue, multiplicity: multiplicity, tolerance: tolerance, using: &execution)
    }

    /// Exact Boehm refinement after the caller has resolved the input domain and multiplicity.
    func insertingInteriorKnot<A: ExactScalarAdmission & ~Copyable>(
        _ insertionValue: Double, multiplicity: Int, tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        let span = try knotSpan(containing: insertionValue, using: &execution)
        let lastControlPointIndex = controlPointCount - 1
        let newControlCount = controlPointCount.addingReportingOverflow(1)
        guard !newControlCount.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: newControlCount.partialValue, of: HomogeneousPoint.self))
        var updatedWeightedPoints = Array(
            repeating: HomogeneousPoint.zero,
            count: newControlCount.partialValue
        )
        let weightedPoints = try homogeneousControlPoints(using: &execution)

        let unchangedPrefixEnd = span - degree
        if unchangedPrefixEnd >= 0 {
            for index in 0...unchangedPrefixEnd {
                try execution.consumeWork(1)
                updatedWeightedPoints[index] = weightedPoints[index]
            }
        }
        let unchangedSuffixStart = span - multiplicity + 1
        if unchangedSuffixStart <= lastControlPointIndex + 1 {
            for index in unchangedSuffixStart...(lastControlPointIndex + 1) {
                try execution.consumeWork(1)
                updatedWeightedPoints[index] = weightedPoints[index - 1]
            }
        }
        let blendedStart = span - degree + 1
        let blendedEnd = span - multiplicity
        if blendedStart <= blendedEnd {
            for index in blendedStart...blendedEnd {
                try execution.consumeWork(1)
                let denominator = knots[index + degree] - knots[index]
                guard denominator.isFinite, denominator > 0 else {
                    throw GeometryError.invalidDistance(denominator)
                }
                let alpha = (insertionValue - knots[index]) / denominator
                updatedWeightedPoints[index] = weightedPoints[index]
                    .scaled(by: alpha)
                    .adding(weightedPoints[index - 1].scaled(by: 1.0 - alpha))
            }
        }

        let newKnotCount = knots.count.addingReportingOverflow(1)
        guard !newKnotCount.overflow else { throw ExactScalarFailure.countOverflow }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: newKnotCount.partialValue, of: Double.self))
        var newKnots: [Double] = []
        newKnots.reserveCapacity(newKnotCount.partialValue)
        for knot in knots.prefix(span + 1) { try execution.consumeWork(1); newKnots.append(knot) }
        newKnots.append(insertionValue)
        for knot in knots.suffix(from: span + 1) { try execution.consumeWork(1); newKnots.append(knot) }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: updatedWeightedPoints.count, of: Point3D.self))
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: updatedWeightedPoints.count, of: Double.self))
        let updatedCurve = try BSplineCurve3D(
            degree: degree, knots: newKnots,
            controlPoints: updatedWeightedPoints.map { try execution.consumeWork(1); return try $0.point() },
            weights: updatedWeightedPoints.map { try execution.consumeWork(1); return $0.weight }
        )
        try updatedCurve.validate(tolerance: tolerance, using: &execution)
        return updatedCurve
    }

    public func trimmed<A: ExactScalarAdmission & ~Copyable>(
        from startParameter: Double,
        to endParameter: Double,
        expansionOptions: PeriodicBSplineExpansionOptions = .init(),
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        if isPeriodic {
            return try periodicRestriction(from: startParameter, to: endParameter,
                options: expansionOptions, tolerance: tolerance, using: &execution)
        }
        let start = try canonicalKnotValue(startParameter, tolerance: tolerance, using: &execution)
        let end = try canonicalKnotValue(endParameter, tolerance: tolerance, using: &execution)
        if case let .closed(lower, upper) = domain,
           start == lower,
           end == upper {
            return self
        }
        return try BSplineCurvePatchAssembler().trimmedCurve(
            source: self,
            lower: start,
            upper: end,
            tolerance: tolerance, using: &execution
        )
    }

    public func validate(tolerance: ModelingTolerance) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try validate(tolerance: tolerance, using: &execution)
    }

    /// The composing caller owns admission for every original source visit.
    package func validate<A: ExactScalarAdmission & ~Copyable>(tolerance: ModelingTolerance, using execution: inout A) throws {
        try execution.consumeWork(1); try tolerance.validate()
        guard degree >= 1, degree < controlPoints.count else {
            throw GeometryError.invalidDistance(0.0)
        }
        for point in controlPoints {
            try execution.consumeWork(1); try execution.consumeWork(1); try execution.consumeWork(1)
            try point.validate()
        }
        try validateWeights(using: &execution)
        try validateKnots(using: &execution)
        try execution.consumeWork(1); try domain.validate(tolerance: tolerance)
        try validatePeriodicity(tolerance: tolerance, using: &execution)
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
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

    public func parameterDerivatives(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> CurveParameterDerivatives {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        return try parameterDerivatives(at: parameter, tolerance: tolerance, using: &execution)
    }

    public func point<A: ExactScalarAdmission & ~Copyable>(at parameter: Double, tolerance: ModelingTolerance, using execution: inout A) throws -> Point3D {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        return try pointAssumingValid(at: parameter, tolerance: tolerance, using: &execution)
    }

    func pointAssumingValid<A: ExactScalarAdmission & ~Copyable>(
        at parameter: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Point3D {
        try execution.consumeWork(1)
        guard try domain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clamped = try basisParameter(parameter, tolerance: tolerance)
        let basis = try BSplineBasis.nonzeroValues(
            parameter: clamped,
            degree: degree,
            knots: knots,
            count: controlPointCount, using: &execution
        )
        let position = try rationalPoint(basis: basis, using: &execution)
        return Point3D(x: position.x, y: position.y, z: position.z)
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

    public func parameterDerivatives<A: ExactScalarAdmission & ~Copyable>(
        at parameter: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> CurveParameterDerivatives {
        try execution.consumeWork(1)
        try validate(tolerance: tolerance, using: &execution)
        return try parameterDerivativesAssumingValid(
            at: parameter,
            tolerance: tolerance, using: &execution
        )
    }

    package func parameterDerivativesAssumingValid<A: ExactScalarAdmission & ~Copyable>(
        at parameter: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> CurveParameterDerivatives {
        try execution.consumeWork(1)
        guard try domain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let clamped = try basisParameter(parameter, tolerance: tolerance)
        if degree == 3, controlPointCount == 4, knots.count == 8,
           try weights.allSatisfy({ try execution.consumeWork(1); return $0 == 1 }),
           knots[0] == knots[3], knots[4] == knots[7] {
            let width = knots[4] - knots[3]
            let t = (clamped - knots[3]) / width
            let s = 1 - t
            let a = controlPoints[0] + (controlPoints[1] - controlPoints[0]) * t
            let b = controlPoints[1] + (controlPoints[2] - controlPoints[1]) * t
            let c = controlPoints[2] + (controlPoints[3] - controlPoints[2]) * t
            let d = a + (b - a) * t
            let e = b + (c - b) * t
            let position = d + (e - d) * t
            let v0 = controlPoints[1] - controlPoints[0]
            let v1 = controlPoints[2] - controlPoints[1]
            let v2 = controlPoints[3] - controlPoints[2]
            let first = (v0 * (s * s) + v1 * (2 * s * t) + v2 * (t * t)) * (3 / width)
            let second = ((v1 - v0) * s + (v2 - v1) * t) * (6 / width / width)
            guard position.isFinite, first.isFinite, second.isFinite else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                    tolerance: tolerance,
                    message: "Polynomial B-spline parameter differentiation exceeded the finite numeric range.")
            }
            return CurveParameterDerivatives(position: position,
                firstDerivative: first, secondDerivative: second)
        }
        let basis = try BSplineBasis.nonzeroDerivativeValues(
            parameter: clamped,
            degree: degree,
            throughDerivativeOrder: 2,
            knots: knots,
            count: controlPointCount, using: &execution
        )
        let derivatives = try rationalDerivatives(
            basis: basis[0],
            firstBasis: basis[1],
            secondBasis: basis[2], using: &execution
        )
        guard derivatives.first.isFinite,
              derivatives.second.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .resourceLimitExceeded,
                tolerance: tolerance,
                message: "Rational B-spline parameter differentiation exceeded the finite numeric range."
            )
        }
        return CurveParameterDerivatives(
            position: derivatives.position,
            firstDerivative: derivatives.first,
            secondDerivative: derivatives.second
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
        let clamped = try basisParameter(parameter, tolerance: tolerance)
        let basis = try BSplineBasis.nonzeroDerivativeValues(
            parameter: clamped,
            degree: degree,
            throughDerivativeOrder: 2,
            knots: knots,
            count: controlPointCount, using: &execution
        )
        let derivatives = try rationalDerivatives(
            basis: basis[0],
            firstBasis: basis[1],
            secondBasis: basis[2], using: &execution
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

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case degree
        case knots
        case controlPoints
        case weights
        case isPeriodic
        case periodicOrigin
    }
#endif

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

    private func validateWeights<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws {
        guard weights.count == controlPointCount else {
            throw GeometryError.invalidDistance(Double(weights.count))
        }
        for weight in weights {
            try execution.consumeWork(1)
            guard weight.isFinite else {
                throw GeometryError.invalidCoordinate(weight)
            }
            guard weight > 0.0 else {
                throw GeometryError.invalidDistance(weight)
            }
        }
    }

    private func validateKnots<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws {
        let total = controlPointCount.addingReportingOverflow(degree)
        guard !total.overflow, total.partialValue < Int.max, knots.count == total.partialValue + 1 else {
            throw GeometryError.invalidDistance(Double(knots.count))
        }
        for knot in knots {
            try execution.consumeWork(1)
            guard knot.isFinite else {
                throw GeometryError.invalidCoordinate(knot)
            }
        }
        for index in 1..<knots.count {
            try execution.consumeWork(1)
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
            upperBound: upperBound,
            using: &execution
        )
    }

    private func validateKnotMultiplicities<A: ExactScalarAdmission & ~Copyable>(
        lowerBound: Double,
        upperBound: Double,
        using execution: inout A
    ) throws {
        var runStart = 0
        while runStart < knots.count {
            try execution.consumeWork(1)
            var runEnd = runStart + 1
            while runEnd < knots.count {
                try execution.consumeWork(1)
                guard knots[runEnd] == knots[runStart] else { break }
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

    private func rationalPoint<A: ExactScalarAdmission & ~Copyable>(
        basis: BSplineBasis.NonzeroValues, using execution: inout A
    ) throws -> Vector3D {
        try execution.consumeWork(1)
        return try rationalVector(try weightedCurveVector(basis: basis, using: &execution))
    }

    private func rationalDerivatives<A: ExactScalarAdmission & ~Copyable>(
        basis: BSplineBasis.NonzeroValues,
        firstBasis: BSplineBasis.NonzeroValues,
        secondBasis: BSplineBasis.NonzeroValues, using execution: inout A
    ) throws -> RationalDerivatives {
        try execution.consumeWork(1)
        let base = try weightedCurveVector(basis: basis, using: &execution)
        let first = try weightedCurveVector(basis: firstBasis, using: &execution)
        let second = try weightedCurveVector(basis: secondBasis, using: &execution)
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

    private func weightedCurveVector<A: ExactScalarAdmission & ~Copyable>(
        basis: BSplineBasis.NonzeroValues, using execution: inout A
    ) throws -> WeightedVector {
        try execution.consumeWork(1)
        var point = Vector3D.zero
        var weightSum = 0.0
        for (offset, value) in basis.values.enumerated() {
            try execution.consumeWork(1)
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

    private func homogeneousControlPoints<A: ExactScalarAdmission & ~Copyable>(using execution: inout A) throws -> [HomogeneousPoint] {
        try execution.consumeWork(1)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: controlPoints.count, of: HomogeneousPoint.self))
        return try controlPoints.indices.map { index in
            try execution.consumeWork(1)
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

    private func canonicalKnotValue<A: ExactScalarAdmission & ~Copyable>(
        _ value: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Double {
        try execution.consumeWork(1)
        let parameterTolerance = domain.parameterResolution(tolerance: tolerance)
        for knot in knots {
            try execution.consumeWork(1)
            if abs(knot - value) <= parameterTolerance { return knot }
        }
        return value
    }

    private func knotMultiplicity<A: ExactScalarAdmission & ~Copyable>(
        at value: Double,
        tolerance: ModelingTolerance, using execution: inout A
    ) throws -> Int {
        try execution.consumeWork(1)
        let parameterTolerance = domain.parameterResolution(tolerance: tolerance)
        var count = 0
        for knot in knots {
            try execution.consumeWork(1)
            if abs(knot - value) <= parameterTolerance { count += 1 }
        }
        return count
    }

    private func knotSpan<A: ExactScalarAdmission & ~Copyable>(containing value: Double, using execution: inout A) throws -> Int {
        try execution.consumeWork(1)
        let lastControlPointIndex = controlPointCount - 1
        if value >= knots[lastControlPointIndex + 1] {
            return lastControlPointIndex
        }
        var lower = degree
        var upper = lastControlPointIndex + 1
        var middle = (lower + upper) / 2
        while value < knots[middle] || value >= knots[middle + 1] {
            try execution.consumeWork(1)
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

#if !hasFeature(Embedded)
extension BSplineCurve3D: Codable {}
extension BSplineCurve3D.DifferentialGeometry: Codable {}
#endif

import CADCore
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

extension BSplineCurve3D {
    /// Constructs a cycle with N independent controls and N+1 cycle knots.
    /// The basis uses the periodic extension, rather than clamped end knots.
    public static func periodic(
        degree: Int, cycleKnots: [Double], controlPoints: [Point3D],
        weights: [Double]? = nil, tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        let count = controlPoints.count
        let (extendedCount, overflow) = count.addingReportingOverflow(degree)
        let (knotCount, knotOverflow) = extendedCount.addingReportingOverflow(degree)
        guard degree >= 1, count > 0, !overflow, !knotOverflow, knotCount < Int.max,
              cycleKnots.count == count + 1,
              let lower = cycleKnots.first, let upper = cycleKnots.last,
              lower.isFinite, upper.isFinite, upper > lower else {
            throw invalidCycle(tolerance)
        }
        let cycleWeights = weights ?? Array(repeating: 1.0, count: count)
        guard cycleWeights.count == count else { throw invalidCycle(tolerance) }
        let period = upper - lower
        guard period.isFinite else { throw invalidCycle(tolerance) }
        let extendedKnots = try Self.translatedPeriodicKnots(degree: degree,
            cycleKnots: Array(cycleKnots.dropLast()), period: period,
            independentControlCount: count, firstCycle: 0, tolerance: tolerance)
        var points = controlPoints
        var extendedWeights = cycleWeights
        points.reserveCapacity(extendedCount)
        extendedWeights.reserveCapacity(extendedCount)
        for index in 0..<degree {
            points.append(controlPoints[index % count])
            extendedWeights.append(cycleWeights[index % count])
        }
        let curve = BSplineCurve3D(
            degree: degree, knots: extendedKnots, controlPoints: points,
            weights: extendedWeights, isPeriodic: true, periodicOrigin: lower
        )
        try curve.validate(tolerance: tolerance)
        return curve
    }

    static func translatedPeriodicKnots(
        degree: Int, cycleKnots: [Double], period: Double,
        independentControlCount: Int, firstCycle: Double, tolerance: ModelingTolerance
    ) throws -> [Double] {
        let (last, overflow) = independentControlCount.addingReportingOverflow(degree)
        let (total, totalOverflow) = last.addingReportingOverflow(degree + 1)
        guard !overflow, !totalOverflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Periodic knot expansion exceeded representable storage.")
        }
        let count = cycleKnots.count
        var result: [Double] = []
        result.reserveCapacity(total)
        for index in -degree...last {
            let quotient = index >= 0 ? index / count : (index + 1) / count - 1
            let remainder = index - quotient * count
            let translated = cycleKnots[remainder] + (firstCycle + Double(quotient)) * period
            guard translated.isFinite else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Periodic knot translation exceeded finite arithmetic.")
            }
            result.append(translated)
        }
        return result
    }

    /// One finite interval representing every parameter of the curve.
    public var fundamentalDomain: ParameterDomain {
        guard degree >= 0, degree < knots.count - 1 else { return .closed(0, 0) }
        let lower = knots[degree]
        let upper = knots[knots.count - degree - 1]
        guard isPeriodic else { return .closed(lower, upper) }
        let origin = periodicOrigin ?? lower
        return .closed(origin, origin + (upper - lower))
    }

    /// The continuity guaranteed by the seam knot multiplicity, independent of sampling.
    public var periodicSeamContinuityOrder: Int? {
        guard isPeriodic, degree >= 1, degree < knots.count else { return nil }
        let lower = knots[degree]
        return degree - knots.filter { $0 == lower }.count
    }

    public func normalizedParameter(_ parameter: Double, tolerance: ModelingTolerance) throws -> Double {
        try validate(tolerance: tolerance)
        guard isPeriodic, case let .closed(lower, _) = fundamentalDomain else {
            throw Self.invalidCycle(tolerance)
        }
        let period = knots[knots.count - degree - 1] - knots[degree]
        return try Self.representative(parameter, origin: lower, period: period, tolerance: tolerance)
    }

    /// Changes the interval of representatives without changing the function C(u).
    public func changingPeriodicOrigin(to origin: Double, tolerance: ModelingTolerance) throws -> BSplineCurve3D {
        try validate(tolerance: tolerance)
        guard isPeriodic else { throw Self.invalidCycle(tolerance) }
        var result = self
        result.periodicOrigin = origin
        try result.validate(tolerance: tolerance)
        return result
    }

    func basisParameter(_ parameter: Double, tolerance: ModelingTolerance) throws -> Double {
        guard isPeriodic else {
            return BSplineBasis.clampedParameter(parameter, knots: knots, degree: degree)
        }
        let lower = knots[degree]
        let period = knots[knots.count - degree - 1] - lower
        return try Self.representative(parameter, origin: lower, period: period, tolerance: tolerance)
    }

    func validatePeriodicity(tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() }) throws {
        try consumeWork()
        guard isPeriodic else {
            guard periodicOrigin == nil else { throw Self.invalidCycle(tolerance) }
            return
        }
        let count = controlPointCount - degree
        guard count > 0, degree >= 1, degree < knots.count else { throw Self.invalidCycle(tolerance) }
        var seamMultiplicity = 0
        for knot in knots {
            try consumeWork()
            if knot == knots[degree] { seamMultiplicity += 1 }
        }
        guard degree >= seamMultiplicity else { throw Self.invalidCycle(tolerance) }
        for index in count..<controlPointCount {
            try consumeWork(); try consumeWork(); try consumeWork(); try consumeWork()
            guard controlPoints[index] == controlPoints[index % count],
                  weights[index] == weights[index % count] else { throw Self.invalidCycle(tolerance) }
        }
        try Self.validatePeriodicAxis(degree: degree, knots: knots,
            controlPointCount: controlPointCount, origin: periodicOrigin, tolerance: tolerance,
            consumeWork: consumeWork)
    }

    /// Checks original cyclic knots in place under the composing caller's admission.
    static func validatePeriodicAxis(
        degree: Int, knots: [Double], controlPointCount: Int, origin: Double?,
        tolerance: ModelingTolerance,
        consumeWork: () throws -> Void = { try CurrentTaskCancellationChecker().checkCancellation() }
    ) throws {
        try consumeWork()
        let independent = controlPointCount.subtractingReportingOverflow(degree)
        guard !independent.overflow, independent.partialValue > 0, degree >= 1,
            degree < knots.count, controlPointCount >= 0, controlPointCount < knots.count else {
            throw invalidCycle(tolerance)
        }
        let count = independent.partialValue
        var multiplicity = 0
        for knot in knots {
            try consumeWork()
            if knot == knots[degree] { multiplicity += 1 }
        }
        guard degree >= multiplicity else { throw invalidCycle(tolerance) }
        let period = knots[controlPointCount] - knots[degree]
        for index in 0..<(knots.count - count) {
            try consumeWork(); try consumeWork()
            let expected = knots[index] + period
            let actual = knots[index + count]
            let resolution = max(abs(expected), abs(actual), period, 1) * Double.ulpOfOne * 16
            guard expected.isFinite, abs(actual - expected) <= resolution else {
                throw invalidCycle(tolerance)
            }
        }
        let lower = origin ?? knots[degree]
        try consumeWork()
        try ParameterDomain.closed(lower, lower + period).validate(tolerance: tolerance)
    }

    static func representative(
        _ parameter: Double, origin: Double, period: Double, tolerance: ModelingTolerance
    ) throws -> Double {
        guard parameter.isFinite, origin.isFinite, period.isFinite, period > 0 else {
            throw invalidCycle(tolerance)
        }
        let difference = parameter - origin
        var remainder: Double
        if difference.isFinite {
            remainder = difference.truncatingRemainder(dividingBy: period)
        } else {
            var first = parameter.truncatingRemainder(dividingBy: period)
            var second = origin.truncatingRemainder(dividingBy: period)
            if first < 0 { first += period }
            if second < 0 { second += period }
            remainder = first - second
        }
        if remainder < 0 { remainder += period }
        let result = origin + remainder
        let upper = origin + period
        guard result.isFinite, upper.isFinite, upper > origin else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "The periodic representative interval exceeds finite parameter resolution.")
        }
        return result >= upper ? origin : result
    }

    private static func invalidCycle(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
            message: "A periodic B-spline requires finite translated knots, a positive homogeneous cycle and a representable origin.")
    }
}

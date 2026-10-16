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
    func periodicRestriction<A: ExactScalarAdmission & ~Copyable>(
        from lower: Double, to upper: Double,
        options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        let plan = try PeriodicBSplineEditPlan.restriction(degree: degree, knots: knots,
            controlPointCount: controlPointCount, periodic: true,
            lower: lower, upper: upper, tolerance: tolerance)
        try plan.admit(options, tolerance: tolerance)
        let expanded = try periodicWindow(firstCycle: plan.firstCycle, cycleCount: plan.cycleCount,
            reservedControlPoints: plan.reservedControlPoints, options: options, tolerance: tolerance, using: &execution)
        guard expanded.knots[degree] < lower, expanded.knots[expanded.controlPointCount] > upper else {
            throw expansionFailure(tolerance)
        }
        return try BSplineCurveSegmentExtractor().segment(
            of: expanded, from: lower, to: upper, tolerance: tolerance, using: &execution)
    }

    func periodicWindow<A: ExactScalarAdmission & ~Copyable>(
        firstCycle: Double, cycleCount: Int, reservedControlPoints: Int,
        options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance, using execution: inout A
    ) throws -> BSplineCurve3D {
        try execution.consumeWork(1)
        let count = controlPointCount - degree
        let (independentCount, countOverflow) = cycleCount.multipliedReportingOverflow(by: count)
        let (expandedCount, degreeOverflow) = independentCount.addingReportingOverflow(degree)
        let (workspaceCount, workspaceOverflow) = expandedCount.addingReportingOverflow(reservedControlPoints)
        guard cycleCount > 0, reservedControlPoints >= 0, !countOverflow, !degreeOverflow,
              !workspaceOverflow, workspaceCount <= options.maximumControlPointCount else {
            throw expansionFailure(tolerance)
        }
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: count, of: Double.self))
        let expandedKnots = try Self.translatedPeriodicKnots(degree: degree,
            cycleKnots: Array(knots[degree..<(degree + count)]),
            period: knots[controlPointCount] - knots[degree],
            independentControlCount: independentCount, firstCycle: firstCycle, tolerance: tolerance, using: &execution)
        var points: [Point3D] = []
        var expandedWeights: [Double] = []
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: expandedCount, of: Point3D.self))
        points.reserveCapacity(expandedCount)
        try execution.retainStorage(bytes: exactScalarPayloadBytes(count: expandedCount, of: Double.self))
        expandedWeights.reserveCapacity(expandedCount)
        for index in 0..<expandedCount {
            try execution.consumeWork(1)
            points.append(controlPoints[index % count])
            expandedWeights.append(weights[index % count])
        }
        let expanded = BSplineCurve3D(degree: degree, knots: expandedKnots,
            controlPoints: points, weights: expandedWeights)
        try expanded.validate(tolerance: tolerance, using: &execution)
        return expanded
    }

    func expansionFailure(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "The periodic edit exceeds its storage, insertion-work or finite knot resolution budget.")
    }

    func validatePeriodicDerivativeCertificate(
        over interval: ScalarInterval, tolerance: ModelingTolerance
    ) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try validatePeriodicDerivativeCertificate(over: interval, tolerance: tolerance, using: &execution)
    }

    static func validatePeriodicDerivativeCertificate(
        degree: Int, knots: [Double], controlPointCount: Int,
        over interval: ScalarInterval, tolerance: ModelingTolerance
    ) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try validatePeriodicDerivativeCertificate(degree: degree, knots: knots, controlPointCount: controlPointCount,
            over: interval, tolerance: tolerance, using: &execution)
    }

    /// A finite second-derivative bound requires a C1 certificate at every interior knot.
    func validatePeriodicDerivativeCertificate<A: ExactScalarAdmission & ~Copyable>(
        over interval: ScalarInterval, tolerance: ModelingTolerance, using execution: inout A
    ) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
        guard isPeriodic else { return }
        try Self.validatePeriodicDerivativeCertificate(degree: degree, knots: knots,
            controlPointCount: controlPointCount, over: interval, tolerance: tolerance, using: &execution)
    }

    static func validatePeriodicDerivativeCertificate<A: ExactScalarAdmission & ~Copyable>(
        degree: Int, knots: [Double], controlPointCount: Int,
        over interval: ScalarInterval, tolerance: ModelingTolerance, using execution: inout A
    ) throws {
        try execution.checkpoint()
        try execution.consumeWork(1)
        let period = knots[controlPointCount] - knots[degree]
        var index = degree
        while index < controlPointCount {
            try execution.consumeWork(1)
            let knot = knots[index]
            var first = index
            while first > 0 {
                try execution.consumeWork(1)
                guard knots[first - 1] == knot else { break }
                first -= 1
            }
            var next = index + 1
            while next < knots.count {
                try execution.consumeWork(1)
                guard knots[next] == knot else { break }
                next += 1
            }
            try execution.consumeWork(1)
            if next - first >= degree {
                try execution.consumeWork(1)
                let cycle = floor((interval.lower - knot) / period) + 1
                let interior = knot + cycle * period
                guard interior.isFinite, interior > interval.lower else {
                    throw PeriodicBSplineEditPlan.failure(tolerance)
                }
                if interior < interval.upper {
                    throw KernelError(phase: .geometry, code: .singularGeometry, tolerance: tolerance,
                        message: "A finite smooth derivative certificate requires splitting at a periodic C0 knot.")
                }
            }
            index = next
        }
    }
}

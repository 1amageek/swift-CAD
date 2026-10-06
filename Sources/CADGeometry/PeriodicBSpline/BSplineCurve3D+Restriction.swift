import CADCore
import Foundation

extension BSplineCurve3D {
    func periodicRestriction(
        from lower: Double, to upper: Double,
        options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        let plan = try PeriodicBSplineEditPlan.restriction(degree: degree, knots: knots,
            controlPointCount: controlPointCount, periodic: true,
            lower: lower, upper: upper, tolerance: tolerance)
        try plan.admit(options, tolerance: tolerance)
        let expanded = try periodicWindow(firstCycle: plan.firstCycle, cycleCount: plan.cycleCount,
            reservedControlPoints: plan.reservedControlPoints, options: options, tolerance: tolerance)
        guard expanded.knots[degree] < lower, expanded.knots[expanded.controlPointCount] > upper else {
            throw expansionFailure(tolerance)
        }
        return try BSplineCurveSegmentExtractor().segment(
            of: expanded, from: lower, to: upper, tolerance: tolerance)
    }

    func periodicWindow(
        firstCycle: Double, cycleCount: Int, reservedControlPoints: Int,
        options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        let count = controlPointCount - degree
        let (independentCount, countOverflow) = cycleCount.multipliedReportingOverflow(by: count)
        let (expandedCount, degreeOverflow) = independentCount.addingReportingOverflow(degree)
        let (workspaceCount, workspaceOverflow) = expandedCount.addingReportingOverflow(reservedControlPoints)
        guard cycleCount > 0, reservedControlPoints >= 0, !countOverflow, !degreeOverflow,
              !workspaceOverflow, workspaceCount <= options.maximumControlPointCount else {
            throw expansionFailure(tolerance)
        }
        let expandedKnots = try Self.translatedPeriodicKnots(degree: degree,
            cycleKnots: Array(knots[degree..<(degree + count)]),
            period: knots[controlPointCount] - knots[degree],
            independentControlCount: independentCount, firstCycle: firstCycle, tolerance: tolerance)
        var points: [Point3D] = []
        var expandedWeights: [Double] = []
        points.reserveCapacity(expandedCount)
        expandedWeights.reserveCapacity(expandedCount)
        for index in 0..<expandedCount {
            points.append(controlPoints[index % count])
            expandedWeights.append(weights[index % count])
        }
        let expanded = BSplineCurve3D(degree: degree, knots: expandedKnots,
            controlPoints: points, weights: expandedWeights)
        try expanded.validate(tolerance: tolerance)
        return expanded
    }

    func expansionFailure(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "The periodic edit exceeds its storage, insertion-work or finite knot resolution budget.")
    }

    /// A finite second-derivative bound requires a C1 certificate at every interior knot.
    func validatePeriodicDerivativeCertificate(
        over interval: ScalarInterval, tolerance: ModelingTolerance
    ) throws {
        guard isPeriodic else { return }
        try Self.validatePeriodicDerivativeCertificate(degree: degree, knots: knots,
            controlPointCount: controlPointCount, over: interval, tolerance: tolerance)
    }

    static func validatePeriodicDerivativeCertificate(
        degree: Int, knots: [Double], controlPointCount: Int,
        over interval: ScalarInterval, tolerance: ModelingTolerance
    ) throws {
        let period = knots[controlPointCount] - knots[degree]
        var index = degree
        while index < controlPointCount {
            let knot = knots[index]
            var first = index
            while first > 0, knots[first - 1] == knot { first -= 1 }
            var next = index + 1
            while next < knots.count, knots[next] == knot { next += 1 }
            if next - first >= degree {
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

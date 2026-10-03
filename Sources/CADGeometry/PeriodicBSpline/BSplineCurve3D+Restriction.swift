import CADCore
import Foundation

extension BSplineCurve3D {
    func periodicRestriction(
        from lower: Double, to upper: Double,
        options: PeriodicBSplineExpansionOptions, tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        try options.validate(tolerance: tolerance)
        guard lower.isFinite, upper.isFinite, upper > lower else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "A periodic restriction requires a finite increasing interval.")
        }
        let count = controlPointCount - degree
        let origin = knots[degree]
        let period = knots[controlPointCount] - origin
        // Whole-cycle padding makes both extraction boundaries interior knots.
        let firstCycle = floor((lower - origin) / period) - 1
        let lastCycle = ceil((upper - origin) / period) + 1
        let cycles = lastCycle - firstCycle
        let (workspacePadding, paddingOverflow) = degree.multipliedReportingOverflow(by: 3)
        guard !paddingOverflow else { throw expansionFailure(tolerance) }
        let available = options.maximumControlPointCount - workspacePadding
        guard firstCycle.isFinite, lastCycle.isFinite, cycles.isFinite,
              available > 0, cycles > 0, cycles <= Double(available / count),
              let cycleCount = Int(exactly: cycles) else {
            throw expansionFailure(tolerance)
        }
        let (independentCount, countOverflow) = cycleCount.multipliedReportingOverflow(by: count)
        let (expandedCount, degreeOverflow) = independentCount.addingReportingOverflow(degree)
        let (lastKnotIndex, knotOverflow) = expandedCount.addingReportingOverflow(degree)
        guard !countOverflow, !degreeOverflow, !knotOverflow, lastKnotIndex < Int.max,
              expandedCount <= options.maximumControlPointCount else {
            throw expansionFailure(tolerance)
        }
        let cycleKnots = Array(knots[degree..<(degree + count)])
        var expandedKnots: [Double] = []
        expandedKnots.reserveCapacity(lastKnotIndex + 1)
        for index in -degree...expandedCount {
            let quotient = index >= 0 ? index / count : (index + 1) / count - 1
            let remainder = index - quotient * count
            let translated = cycleKnots[remainder] + (firstCycle + Double(quotient)) * period
            guard translated.isFinite else { throw expansionFailure(tolerance) }
            expandedKnots.append(translated)
        }
        guard expandedKnots[degree] < lower, expandedKnots[expandedCount] > upper else {
            throw expansionFailure(tolerance)
        }
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
        return try BSplineCurveSegmentExtractor().segment(
            of: expanded, from: lower, to: upper, tolerance: tolerance)
    }

    private func expansionFailure(_ tolerance: ModelingTolerance) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
            message: "The periodic restriction exceeds its control budget or finite knot resolution.")
    }

    /// A finite second-derivative bound requires a C1 certificate at every interior knot.
    func validatePeriodicDerivativeCertificate(
        over interval: ScalarInterval, tolerance: ModelingTolerance
    ) throws {
        guard isPeriodic else { return }
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
                    throw expansionFailure(tolerance)
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

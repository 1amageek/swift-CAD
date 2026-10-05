import CADCore

/// Exact slice roots steer whole-rectangle real graph certification.
struct OriginalNativeCurveCurveRegularBranchSeed {
    func certificate(common: OriginalNativeCurveCurveCommonFactor,
                     first: RationalBezierCurveJetEncloser.NativeSpan, firstRange: ScalarInterval,
                     second: RationalBezierCurveJetEncloser.NativeSpan, secondRange: ScalarInterval,
                     budget: inout NativeCurveCurveContactBudget) throws -> NativeCurveCurveAlgebraicCorrespondence? {
        try certificate(common: common, firstRange: firstRange, secondRange: secondRange,
            firstNativeSpan: first.index, secondNativeSpan: second.index,
            maximumDepth: budget.maximumDepth, budget: &budget)
    }

    func certificate(common: OriginalNativeCurveCurveCommonFactor,
                     firstRange: ScalarInterval, secondRange: ScalarInterval,
                     firstNativeSpan: Int, secondNativeSpan: Int, maximumDepth: Int,
                     budget: inout NativeCurveCurveContactBudget) throws -> NativeCurveCurveAlgebraicCorrespondence? {
        guard maximumDepth >= 0, maximumDepth <= budget.maximumDepth else { throw budget.exhausted() }
        for independentAlongU in [true, false] {
            let independent = independentAlongU ? firstRange : secondRange
            let dependent = independentAlongU ? secondRange : firstRange
            let station = independent.midpoint
            guard station > independent.lower, station < independent.upper else { continue }
            let exactStation = try ExactRationalCoefficient.originalDouble(station, usage: &budget)
            let slice = try common.factor.restricted(alongU: independentAlongU,
                station: exactStation, usage: &budget)
            // A zero slice is an entire axis locus, not an isolated slice root.
            // Existing factor-domain subdivision remains responsible for it.
            guard !slice.isZero, slice.uDegree > 0 else { continue }
            let lower = try ExactRationalCoefficient.originalDouble(dependent.lower, usage: &budget)
            let upper = try ExactRationalCoefficient.originalDouble(dependent.upper, usage: &budget)
            let divisor = try ExactRationalCoefficient.originalDouble(32, usage: &budget)
            let targetWidth = try upper.subtracting(lower, usage: &budget).divided(by: divisor, usage: &budget)
            let roots = try ExactUnivariateRootIsolator().isolate(slice, lower: lower, upper: upper,
                maximumDepth: maximumDepth, usage: &budget)
            for isolation in roots {
                let root = try ExactAlgebraicRealRoot(polynomial: slice, isolation: isolation, usage: &budget)
                    .refined(maximumWidth: targetWidth, maximumDepth: maximumDepth, usage: &budget)
                let rootLower = try root.isolation.lower.outwardInterval(usage: &budget).lower
                let rootUpper = try root.isolation.upper.outwardInterval(usage: &budget).upper
                try budget.work(8)
                // Padding only chooses a candidate rectangle. Full original edge
                // signs below must certify that its interior contains a branch.
                let padding = max((rootUpper - rootLower) * 0.5, dependent.width / 256)
                let candidateLower = max(dependent.lower, (rootLower - padding).nextDown)
                let candidateUpper = min(dependent.upper, (rootUpper + padding).nextUp)
                guard candidateLower.isFinite, candidateUpper.isFinite,
                      candidateLower < candidateUpper else { continue }
                let dependentCandidate = try ScalarInterval(lower: candidateLower, upper: candidateUpper)
                var independentCandidate = independent
                var depth = root.isolation.isolationDepth
                while depth <= maximumDepth {
                    try budget.visitExactCell(depth: depth)
                    let domain = independentAlongU
                        ? SurfaceParameterBox(u: independentCandidate, v: dependentCandidate)
                        : SurfaceParameterBox(u: dependentCandidate, v: independentCandidate)
                    if let receipt = try certificate(common: common, over: domain,
                        independentAlongU: independentAlongU, firstNativeSpan: firstNativeSpan,
                        secondNativeSpan: secondNativeSpan, budget: &budget) { return receipt }
                    guard depth < maximumDepth else { break }
                    try budget.work(4)
                    let low = independentCandidate.lower + (station - independentCandidate.lower) * 0.5
                    let high = station + (independentCandidate.upper - station) * 0.5
                    guard low > independentCandidate.lower, low < station,
                          high > station, high < independentCandidate.upper else { break }
                    independentCandidate = try ScalarInterval(lower: low, upper: high)
                    depth += 1
                }
            }
        }
        return nil
    }

    func certificate(common: OriginalNativeCurveCurveCommonFactor, over domain: SurfaceParameterBox,
                     independentAlongU: Bool, firstNativeSpan: Int, secondNativeSpan: Int,
                     budget: inout NativeCurveCurveContactBudget) throws -> NativeCurveCurveAlgebraicCorrespondence? {
        let derivative = try (independentAlongU ? common.derivativeV : common.derivativeU)
            .enclosure(over: domain, usage: &budget)
        guard derivative.absoluteLowerBound > 0 else { return nil }
        let dependent = independentAlongU ? domain.v : domain.u
        let lower = try ScalarInterval(lower: dependent.lower, upper: dependent.lower)
        let upper = try ScalarInterval(lower: dependent.upper, upper: dependent.upper)
        let lowDomain = independentAlongU ? SurfaceParameterBox(u: domain.u, v: lower)
            : SurfaceParameterBox(u: lower, v: domain.v)
        let highDomain = independentAlongU ? SurfaceParameterBox(u: domain.u, v: upper)
            : SurfaceParameterBox(u: upper, v: domain.v)
        let low = try common.factor.enclosure(over: lowDomain, usage: &budget)
        let high = try common.factor.enclosure(over: highDomain, usage: &budget)
        guard (low.upper < 0 && high.lower > 0) || (low.lower > 0 && high.upper < 0) else { return nil }
        try budget.retainExactStorage(1)
        return NativeCurveCurveAlgebraicCorrespondence(parameters: domain, commonFactor: common.factor,
            originalEquationQuotients: common.quotients, dependentParameter: independentAlongU ? .second : .first,
            firstNativeSpan: firstNativeSpan, secondNativeSpan: secondNativeSpan)
    }
}

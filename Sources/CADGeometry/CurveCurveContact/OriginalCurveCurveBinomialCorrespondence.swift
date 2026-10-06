import CADCore

/// Exact reducible source factors retain separate real correspondence sectors.
struct OriginalCurveCurveBinomialCorrespondence {
    func certificate(common: OriginalNativeCurveCurveCommonFactor,
        over domain: SurfaceParameterBox, firstNativeSpan: Int, secondNativeSpan: Int,
        maximumDepth: Int, budget: inout NativeCurveCurveContactBudget) throws
        -> NativeCurveCurveAlgebraicCorrespondence? {
        guard maximumDepth >= 0, maximumDepth <= budget.maximumDepth else { throw budget.exhausted() }
        guard let source = try OriginalRationalBinomialBranches.proven(original: common.factor,
            usage: &budget) else { return nil }
        for factor in source.factors {
            let branch = try OriginalNativeCurveCurveCommonFactor(retainingSubfactor: factor,
                of: common, budget: &budget)
            if let receipt = try OriginalCurveCurveCuspCorrespondence().certificate(common: branch,
                over: domain, firstNativeSpan: firstNativeSpan, secondNativeSpan: secondNativeSpan,
                maximumDepth: maximumDepth, budget: &budget) { return receipt }
            for alongU in [true, false] {
                guard let graph = try ExactMonotoneRectangleGraphProducer.graph(of: branch.factor,
                    over: domain, freeAlongU: alongU, maximumDepth: maximumDepth, usage: &budget) else { continue }
                if let receipt = try OriginalNativeCurveCurveClippedCorrespondence().certificate(common: branch,
                    graph: graph, firstNativeSpan: firstNativeSpan, secondNativeSpan: secondNativeSpan,
                    budget: &budget) { return receipt }
            }
        }
        return nil
    }
}

import CADCore

/// Original quadratic branches retain separate whole real correspondence sectors.
struct OriginalCurveCurveQuadraticCorrespondence {
    func certificate(common: OriginalNativeCurveCurveCommonFactor,
        over domain: SurfaceParameterBox, firstNativeSpan: Int, secondNativeSpan: Int,
        maximumDepth: Int, budget: inout NativeCurveCurveContactBudget) throws
        -> NativeCurveCurveAlgebraicCorrespondence? {
        guard maximumDepth >= 0, maximumDepth <= budget.maximumDepth else { throw budget.exhausted() }
        guard let branches = try OriginalRationalQuadraticBranches.proven(original: common.factor,
            usage: &budget) else { return nil }
        try budget.retainExactStorage(2)
        for source in [branches.first, branches.second] {
            let branch = try OriginalNativeCurveCurveCommonFactor(retainingSubfactor: source,
                of: common, budget: &budget)
            guard let graph = try ExactMonotoneRectangleGraphProducer.graph(of: branch.factor,
                over: domain, freeAlongU: branches.freeAlongU,
                maximumDepth: maximumDepth, usage: &budget) else { continue }
            if let receipt = try OriginalNativeCurveCurveClippedCorrespondence().certificate(
                common: branch, graph: graph, firstNativeSpan: firstNativeSpan,
                secondNativeSpan: secondNativeSpan, budget: &budget) { return receipt }
        }
        // Separate original branch clips prove no absence in the distance domain.
        return nil
    }
}

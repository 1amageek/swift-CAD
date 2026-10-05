import CADCore

/// Consumes an exact original cusp map without replacing native contact parameters.
struct OriginalCurveCurveCuspCorrespondence {
    func certificate(common: OriginalNativeCurveCurveCommonFactor,
        over domain: SurfaceParameterBox, firstNativeSpan: Int, secondNativeSpan: Int,
        maximumDepth: Int, budget: inout NativeCurveCurveContactBudget) throws
        -> NativeCurveCurveAlgebraicCorrespondence? {
        guard maximumDepth >= 0, maximumDepth <= budget.maximumDepth else { throw budget.exhausted() }
        guard let cusp = try OriginalRationalBinomialCusp.proven(original: common.factor,
            usage: &budget) else { return nil }
        let clipped = try cusp.clipped(over: domain, maximumDepth: maximumDepth, usage: &budget)
        // Complete clipping retains isolated stations separately. An empty
        // positive sector cannot exclude nearby distance-tolerance contacts.
        guard !clipped.spans.isEmpty else { return nil }
        try budget.retainExactStorage(1)
        return NativeCurveCurveAlgebraicCorrespondence(parameters: domain,
            commonFactor: common.factor, originalEquationQuotients: common.quotients,
            dependentParameter: .polynomialMap,
            firstNativeSpan: firstNativeSpan, secondNativeSpan: secondNativeSpan,
            originalPolynomialParameterDomain: clipped)
    }
}

import CADCore

/// Materializes the complete isolated original factor zero with unchanged native spatial fidelity.
struct OriginalNativeCurveCurveIsolatedFactorContact {
    func certificate(polynomial: OriginalNativeCurveCurvePolynomial,
                     first: RationalBezierCurveJetEncloser.NativeSpan, firstRange: ScalarInterval,
                     second: RationalBezierCurveJetEncloser.NativeSpan, secondRange: ScalarInterval,
                     firstJetWork: Int, secondJetWork: Int,
                     budget: inout NativeCurveCurveContactBudget) throws -> [OriginalNativeCurveCurveCriticalContact.Contact]? {
        guard let common = polynomial.commonFactor,
              let proof = try OriginalCurveCurveIsolatedFactorRoots().certificate(common: common,
                over: SurfaceParameterBox(u: firstRange, v: secondRange),
                maximumDepth: budget.maximumDepth, budget: &budget) else { return nil }
        return try OriginalNativeCurveCurveCriticalContact().materialize(roots: proof.roots,
            axes: proof.axes, first: first, firstRange: firstRange,
            second: second, secondRange: secondRange, firstJetWork: firstJetWork,
            secondJetWork: secondJetWork, maximumDepth: budget.maximumDepth, budget: &budget)
    }
}

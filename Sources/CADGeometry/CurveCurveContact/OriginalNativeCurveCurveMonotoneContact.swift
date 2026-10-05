import CADCore

/// Complete original regular-factor coverage, including boundary-only contacts.
struct OriginalNativeCurveCurveMonotoneContact {
    enum Result {
        case continuous(NativeCurveCurveAlgebraicCorrespondence)
        case isolated([OriginalNativeCurveCurveCriticalContact.Contact])
    }

    func certificate(polynomial: OriginalNativeCurveCurvePolynomial,
                     first: RationalBezierCurveJetEncloser.NativeSpan, firstRange: ScalarInterval,
                     second: RationalBezierCurveJetEncloser.NativeSpan, secondRange: ScalarInterval,
                     firstJetWork: Int, secondJetWork: Int,
                     budget: inout NativeCurveCurveContactBudget) throws -> Result? {
        guard let common = polynomial.commonFactor else { return nil }
        let domain = SurfaceParameterBox(u: firstRange, v: secondRange)
        for independentAlongU in [true, false] {
            guard let graph = try ExactMonotoneRectangleGraphProducer.graph(of: common.factor,
                over: domain, freeAlongU: independentAlongU,
                maximumDepth: budget.maximumDepth, usage: &budget) else { continue }
            if !graph.spans.isEmpty {
                if let receipt = try OriginalNativeCurveCurveClippedCorrespondence().certificate(
                    common: common, graph: graph, firstNativeSpan: first.index,
                    secondNativeSpan: second.index, budget: &budget) { return .continuous(receipt) }
                // An exact sector without representable positive-width bounds is
                // not replaced by an isolated or empty classification.
                continue
            }
            try budget.work(common.quotients.count)
            guard let axis = common.quotients.indices.first(where: {
                let value = common.quotients[$0]
                return !value.isZero && value.uDegree == 0 && value.vDegree == 0
            }) else { continue }
            // One original projected equation is equivalent to this factor.
            // The exhaustive monotone cover has no continuous sector, so its
            // retained isolated stations cover every projected root here.
            let roots = try graph.isolatedRoots(maximumDepth: budget.maximumDepth, usage: &budget)
            return .isolated(try OriginalNativeCurveCurveCriticalContact().materialize(
                roots: roots, axes: (axis, axis == 0 ? 1 : 0), first: first, firstRange: firstRange,
                second: second, secondRange: secondRange, firstJetWork: firstJetWork,
                secondJetWork: secondJetWork, maximumDepth: budget.maximumDepth, budget: &budget))
        }
        return nil
    }
}

import CADCore

/// Complete isolated original factor authority independent of the spatial jet representation.
struct OriginalCurveCurveIsolatedFactorRoots {
    struct Proof {
        let axes: (Int, Int)
        let roots: [ExactBivariateSystemRoot]
    }

    enum Outcome {
        case isolated(Proof)
        case continuous(SurfaceParameterBox)
    }

    func certificate(common: OriginalNativeCurveCurveCommonFactor, over domain: SurfaceParameterBox,
        maximumDepth: Int, budget: inout NativeCurveCurveContactBudget) throws -> Proof? {
        switch try outcome(common: common, over: domain, maximumDepth: maximumDepth, budget: &budget) {
        case .isolated(let proof): return proof
        case .continuous, .none: return nil
        }
    }

    func outcome(common: OriginalNativeCurveCurveCommonFactor, over domain: SurfaceParameterBox,
                     maximumDepth: Int, budget: inout NativeCurveCurveContactBudget) throws -> Outcome? {
        guard maximumDepth >= 0, maximumDepth <= budget.maximumDepth else { throw budget.exhausted() }
        try budget.work(common.quotients.count)
        // One original coordinate equation is equivalent to the factor, so
        // no off-factor projected contacts are excluded by this zero cover.
        let axis = common.quotients.indices.first(where: {
            let value = common.quotients[$0]
            return !value.isZero && value.uDegree == 0 && value.vDegree == 0
        })
        let authority = try OriginalRationalZeroSetAuthority(original: common.factor, usage: &budget)
        let projection = try OriginalRationalPlaneCurveProjection(original: authority,
            over: domain, maximumDepth: maximumDepth, usage: &budget)
        if let roots = try projection.finiteOriginalRoots(usage: &budget) {
            if let axis, !roots.isEmpty {
                return .isolated(Proof(axes: (axis, axis == 0 ? 1 : 0), roots: roots))
            }
            // Exact zero absence is not original tolerance-contact exclusion.
            return nil
        }
        let atlas = try OriginalRationalPlaneCurveAtlas(retaining: projection,
            maximumDepth: maximumDepth, usage: &budget)
        for strip in atlas.strips {
            for piece in strip.originalCover.pieces {
                try budget.work(1)
                guard piece.domain.u.width > 0, piece.domain.v.width > 0 else { continue }
                // The algebra owner proved the complete graph tube, nonzero
                // transverse derivative and original opposite-edge signs.
                // Every original XYZ equation is divisible by common.factor.
                return .continuous(piece.domain)
            }
        }
        let criticalU = try authority.squareFree.differentiated(alongU: true, usage: &budget)
        let criticalV = try authority.squareFree.differentiated(alongU: false, usage: &budget)
        let roots: [ExactBivariateSystemRoot]
        do {
            try budget.retainExactStorage(3)
            roots = try ExactBivariateSystemSolver.isolatedRoots(of: [authority.squareFree, criticalU, criticalV],
                over: domain, maximumDepth: maximumDepth, usage: &budget)
        } catch let classification as ExactBivariateSystemClassification {
            switch classification { case .positiveDimensionalOriginalIdeal: return nil }
        }
        if !roots.isEmpty, let continuation = try OriginalCurveCurveSingularContinuation().certificate(
            common: common, at: roots, over: domain, maximumDepth: maximumDepth, budget: &budget) {
            return .continuous(continuation)
        }
        return nil
    }
}

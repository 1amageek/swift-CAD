import CADCore

/// Finite projected atlas roots retain the selected original closed-jet fidelity.
struct OriginalAtlasCurveCurveCriticalContact {
    enum Result {
        case nonfiniteProjectedIdeal
        case unresolvedToleranceContact
        case finite([OriginalNativeCurveCurveCriticalContact.Contact])
    }

    func certificate(equations: [ExactBivariatePolynomial], firstRange: ScalarInterval,
                     secondRange: ScalarInterval, parentDepth: Int,
                     selectedJets: (ScalarInterval, ScalarInterval, inout NativeCurveCurveContactBudget) throws
                        -> (SurfaceIntervalVectorJet, SurfaceIntervalVectorJet),
                     budget: inout NativeCurveCurveContactBudget) throws -> Result {
        guard equations.count == 3, parentDepth >= 0, parentDepth <= budget.maximumDepth else { throw budget.exhausted() }
        let depth = budget.maximumDepth - parentDepth
        let domain = SurfaceParameterBox(u: firstRange, v: secondRange)
        var emptyProjection = false
        for axes in [(0, 1), (0, 2), (1, 2)] {
            let roots: [ExactBivariateSystemRoot]
            do {
                try budget.retainExactStorage(2)
                roots = try ExactBivariateSystemSolver.isolatedRoots(of: [equations[axes.0], equations[axes.1]],
                    over: domain, maximumDepth: depth, usage: &budget)
            } catch let classification as ExactBivariateSystemClassification {
                switch classification { case .positiveDimensionalOriginalIdeal: continue }
            }
            guard !roots.isEmpty else { emptyProjection = true; continue }
            return .finite(try materialize(roots: roots, axes: axes, firstRange: firstRange,
                secondRange: secondRange, maximumDepth: depth, selectedJets: selectedJets, budget: &budget))
        }
        return emptyProjection ? .unresolvedToleranceContact : .nonfiniteProjectedIdeal
    }

    func materialize(roots: [ExactBivariateSystemRoot], axes: (Int, Int),
        firstRange: ScalarInterval, secondRange: ScalarInterval, maximumDepth: Int,
        selectedJets: (ScalarInterval, ScalarInterval, inout NativeCurveCurveContactBudget) throws
            -> (SurfaceIntervalVectorJet, SurfaceIntervalVectorJet),
        budget: inout NativeCurveCurveContactBudget) throws -> [OriginalNativeCurveCurveCriticalContact.Contact] {
        let threshold = OutwardScalarInterval.exact(budget.tolerance.distance) * .exact(budget.tolerance.distance)
        let two = try ExactRationalCoefficient.natural(2, usage: &budget)
        let uWidth = try ExactRationalCoefficient.originalDouble(firstRange.upper, usage: &budget)
            .subtracting(.originalDouble(firstRange.lower, usage: &budget), usage: &budget)
        let vWidth = try ExactRationalCoefficient.originalDouble(secondRange.upper, usage: &budget)
            .subtracting(.originalDouble(secondRange.lower, usage: &budget), usage: &budget)
        func squared(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
            .init(lower: max(0, (value.absoluteLowerBound * value.absoluteLowerBound).nextDown),
                  upper: (value.absoluteUpperBound * value.absoluteUpperBound).nextUp)
        }
        try budget.retainExactStorage(roots.count)
        var result: [OriginalNativeCurveCurveCriticalContact.Contact] = []
        for original in roots {
            var root = original
            var targetU = uWidth, targetV = vWidth
            while true {
                let parameters = try root.enclosure(usage: &budget)
                let (a, b) = try selectedJets(parameters.u, parameters.v, &budget)
                let residual = squared(a.x.value - b.x.value) + squared(a.y.value - b.y.value)
                    + squared(a.z.value - b.z.value)
                if residual.lower > threshold.upper { break }
                if residual.upper <= threshold.lower {
                    let position = try CoordinateEnclosure3D(
                        x: ScalarInterval(lower: a.x.value.lower, upper: a.x.value.upper),
                        y: ScalarInterval(lower: a.y.value.lower, upper: a.y.value.upper),
                        z: ScalarInterval(lower: a.z.value.lower, upper: a.z.value.upper))
                    result.append(.init(first: parameters.u, second: parameters.v, axes: axes, position: position, parameterAuthority: .init(root)))
                    break
                }
                guard parameters.u.width > 0 || parameters.v.width > 0 else { throw budget.exhausted() }
                targetU = try targetU.divided(by: two, usage: &budget)
                targetV = try targetV.divided(by: two, usage: &budget)
                root = try root.refined(maximumUWidth: targetU, maximumVWidth: targetV,
                    maximumDepth: maximumDepth, usage: &budget)
            }
        }
        return result
    }
}

import CADCore

/// Exact finite projected contact coverage, followed by unchanged original spatial fidelity.
struct OriginalNativeCurveCurveCriticalContact {
    struct Contact {
        let first: ScalarInterval
        let second: ScalarInterval
        let axes: (Int, Int)
        let position: CoordinateEnclosure3D
        let parameterAuthority: OriginalCurveContactParameterAuthority?
        init(first: ScalarInterval, second: ScalarInterval, axes: (Int, Int),
            position: CoordinateEnclosure3D, parameterAuthority: OriginalCurveContactParameterAuthority? = nil) {
            self.first = first; self.second = second; self.axes = axes; self.position = position
            self.parameterAuthority = parameterAuthority
        }
    }

    enum Result {
        case nonfiniteProjectedIdeal
        case unresolvedToleranceContact
        case finite([Contact])
    }

    func certificate(polynomial: OriginalNativeCurveCurvePolynomial,
                     first: RationalBezierCurveJetEncloser.NativeSpan, firstRange: ScalarInterval,
                     second: RationalBezierCurveJetEncloser.NativeSpan, secondRange: ScalarInterval,
                     firstJetWork: Int, secondJetWork: Int, parentDepth: Int,
                     budget: inout NativeCurveCurveContactBudget) throws -> Result {
        guard polynomial.equations.count == 3, parentDepth >= 0,
              parentDepth <= budget.maximumDepth else { throw budget.exhausted() }
        let maximumDepth = budget.maximumDepth - parentDepth
        let domain = try SurfaceParameterBox(u: firstRange, v: secondRange)
        var emptyProjection = false
        for axes in [(0, 1), (0, 2), (1, 2)] {
            let roots: [ExactBivariateSystemRoot]
            do {
                try budget.retainExactStorage(2)
                roots = try ExactBivariateSystemSolver.isolatedRoots(
                    of: [polynomial.equations[axes.0], polynomial.equations[axes.1]], over: domain,
                    maximumDepth: maximumDepth, usage: &budget)
            } catch let classification as ExactBivariateSystemClassification {
                switch classification {
                case .positiveDimensionalOriginalIdeal: continue
                }
            }
            // Empty exact projected roots do not exclude a retained tolerance
            // cell. Cancellation, numeric and resource failures still propagate.
            guard !roots.isEmpty else { emptyProjection = true; continue }
            return .finite(try materialize(roots: roots, axes: axes,
                first: first, firstRange: firstRange, second: second, secondRange: secondRange,
                firstJetWork: firstJetWork, secondJetWork: secondJetWork,
                maximumDepth: maximumDepth, budget: &budget))
        }
        return emptyProjection ? .unresolvedToleranceContact : .nonfiniteProjectedIdeal
    }

    func materialize(roots: [ExactBivariateSystemRoot], axes: (Int, Int),
                     first: RationalBezierCurveJetEncloser.NativeSpan, firstRange: ScalarInterval,
                     second: RationalBezierCurveJetEncloser.NativeSpan, secondRange: ScalarInterval,
                     firstJetWork: Int, secondJetWork: Int, maximumDepth: Int,
                     budget: inout NativeCurveCurveContactBudget) throws -> [Contact] {
        let encloser = RationalBezierCurveJetEncloser()
        let threshold = OutwardScalarInterval.exact(budget.tolerance.distance)
            * .exact(budget.tolerance.distance)
        let two = try ExactRationalCoefficient.natural(2, usage: &budget)
        let initialUWidth = try ExactRationalCoefficient.originalDouble(firstRange.upper, usage: &budget)
            .subtracting(ExactRationalCoefficient.originalDouble(firstRange.lower, usage: &budget), usage: &budget)
        let initialVWidth = try ExactRationalCoefficient.originalDouble(secondRange.upper, usage: &budget)
            .subtracting(ExactRationalCoefficient.originalDouble(secondRange.lower, usage: &budget), usage: &budget)
        func square(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
            let lower = value.absoluteLowerBound, upper = value.absoluteUpperBound
            return OutwardScalarInterval(lower: max(0, (lower * lower).nextDown), upper: (upper * upper).nextUp)
        }
        try budget.retainExactStorage(roots.count)
        var contacts: [Contact] = []
        for originalRoot in roots {
            var root = originalRoot
            var targetU = initialUWidth, targetV = initialVWidth
            while true {
                let parameters = try root.enclosure(usage: &budget)
                try budget.work(firstJetWork)
                let a = try encloser.enclosure(of: first, over: parameters.u, tolerance: budget.tolerance)
                try budget.work(secondJetWork)
                let b = try encloser.enclosure(of: second, over: parameters.v, tolerance: budget.tolerance)
                let residual = square(a.x.value - b.x.value) + square(a.y.value - b.y.value)
                    + square(a.z.value - b.z.value)
                // Exact projected existence never waives the original third-coordinate budget.
                if residual.lower > threshold.upper { break }
                if residual.upper <= threshold.lower {
                    let position = try CoordinateEnclosure3D(
                        x: ScalarInterval(lower: a.x.value.lower, upper: a.x.value.upper),
                        y: ScalarInterval(lower: a.y.value.lower, upper: a.y.value.upper),
                        z: ScalarInterval(lower: a.z.value.lower, upper: a.z.value.upper))
                    contacts.append(Contact(first: parameters.u, second: parameters.v,
                        axes: axes, position: position, parameterAuthority: .init(root)))
                    break
                }
                if parameters.u.width == 0, parameters.v.width == 0 { throw budget.exhausted() }
                targetU = try targetU.divided(by: two, usage: &budget)
                targetV = try targetV.divided(by: two, usage: &budget)
                root = try root.refined(maximumUWidth: targetU, maximumVWidth: targetV,
                    maximumDepth: maximumDepth, usage: &budget)
            }
        }
        return contacts
    }
}

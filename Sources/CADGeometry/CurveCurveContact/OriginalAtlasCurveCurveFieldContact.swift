import CADCore

/// Ordered-field contacts preserve original parameter roots and selected 3D jets.
struct OriginalAtlasCurveCurveFieldContact {
    enum Result {
        case continuous(SurfaceParameterBox)
        case isolated([OriginalNativeCurveCurveCriticalContact.Contact])
        case unresolved
    }

    func certificate(equations: [OriginalSingularFieldPlanePolynomial], over domain: SurfaceParameterBox,
        maximumDepth: Int,
        selectedJets: (ScalarInterval, ScalarInterval, inout NativeCurveCurveContactBudget) throws
            -> (SurfaceIntervalVectorJet, SurfaceIntervalVectorJet),
        budget: inout NativeCurveCurveContactBudget) throws -> Result {
        guard equations.count == 3, maximumDepth >= 0 else { throw budget.exhausted() }
        let common: OriginalSingularFieldPlanePolynomial
        var commonCoversEveryContact = false
        do {
            let policy = budget.enterOriginalWordAlgebra()
            defer { budget.restoreOriginalWordAlgebra(policy) }
            common = try OriginalSingularFieldPlaneGCD.gcd(
                OriginalSingularFieldPlaneGCD.gcd(equations[0], equations[1], maximumDepth: budget.maximumAlgebraicDepth, usage: &budget),
                equations[2], maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
            for equation in equations where !common.isZero {
                let quotient = try equation.dividedExactly(by: common, maximumDepth: budget.maximumAlgebraicDepth, usage: &budget)
                if !quotient.isZero, quotient.uDegree <= 0, quotient.vDegree <= 0 {
                    commonCoversEveryContact = true
                }
            }
        }
        if common.isZero {
            // Every original XYZ cross-weight residual is the zero polynomial.
            // Positive native weights are bound by the original selected jets.
            _ = try selectedJets(domain.u, domain.v, &budget)
            return .continuous(domain)
        }
        if common.uDegree > 0 || common.vDegree > 0 {
            let coordinateComponents = try OriginalFieldPlaneCoordinateComponent.all(original: common,
                over: domain, inheritedDepth: 0, maximumDepth: maximumDepth, usage: &budget)
            for component in coordinateComponents {
                let lower = try component.fixedRoot.isolation.lower.outwardInterval(usage: &budget)
                let upper = try component.fixedRoot.isolation.upper.outwardInterval(usage: &budget)
                let originalFixed = component.fixedAlongU ? domain.u : domain.v
                let fixed = try ScalarInterval(lower: max(originalFixed.lower, lower.lower),
                    upper: min(originalFixed.upper, upper.upper))
                let originalParameters = SurfaceParameterBox(u: component.fixedAlongU ? fixed : domain.u,
                    v: component.fixedAlongU ? domain.v : fixed)
                // All XYZ equations divide by this exact original common
                // factor; whole free-variable coefficient vanishing at the
                // retained root proves infinitely many original parameters.
                _ = try selectedJets(originalParameters.u, originalParameters.v, &budget)
                return .continuous(originalParameters)
            }
            let projection = try OriginalSingularFieldPlaneProjection(original: common,
                over: domain, inheritedDepth: 0, maximumDepth: maximumDepth, usage: &budget)
            if let finite = try projection.finiteOriginalRoots(usage: &budget),
                !finite.isEmpty, commonCoversEveryContact {
                let contacts = try materialize(roots: finite, axes: (0, 1), domain: domain,
                    maximumDepth: maximumDepth, selectedJets: selectedJets, budget: &budget)
                if !contacts.isEmpty { return .isolated(contacts) }
            } else if projection.sectors.contains(where: { !$0.fiberRoots.isEmpty }) {
                let atlas = try OriginalFieldPlaneAtlas(retaining: projection,
                    maximumDepth: maximumDepth, usage: &budget)
                for strip in atlas.strips {
                    for piece in strip.originalInteriorCover.pieces {
                        try budget.work(1)
                        guard piece.domain.u.width > 0 else { continue }
                        // All three original equations were divided exactly by
                        // this original factor. The complete regular tube is a
                        // nonconstant native parameter continuum of exact XYZ
                        // contact; interval coordinate width is not coincidence.
                        _ = try selectedJets(piece.domain.u, piece.domain.v, &budget)
                        return .continuous(piece.domain)
                    }
                }
            }
        }
        for axes in [(0, 1), (0, 2), (1, 2)] {
            try RationalAlgebraStorage.retain(2, of: OriginalSingularFieldPlanePolynomial.self, usage: &budget)
            let projected = try OriginalSingularFieldSystemSolver.roots(
                of: [equations[axes.0], equations[axes.1]], over: domain,
                inheritedDepth: 0, maximumDepth: maximumDepth, usage: &budget)
            switch projected {
            case .positiveDimension: continue
            case .finite(let roots):
                guard !roots.isEmpty else { continue }
                let contacts = try materialize(roots: roots, axes: axes, domain: domain,
                    maximumDepth: maximumDepth, selectedJets: selectedJets, budget: &budget)
                if !contacts.isEmpty { return .isolated(contacts) }
            }
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Original Loft events with unresolved
        // ordered-field stationary/boundary-only and tolerance continua require
        // complete original component charts before contact publication. Exact
        // empty ideals cannot exclude original tolerance contacts. The caller
        // retains its original distance test and bounded unresolved subdivision.
        return .unresolved
    }

    private func materialize(roots: [OriginalSingularFieldSystemRoot], axes: (Int, Int),
        domain: SurfaceParameterBox, maximumDepth: Int,
        selectedJets: (ScalarInterval, ScalarInterval, inout NativeCurveCurveContactBudget) throws
            -> (SurfaceIntervalVectorJet, SurfaceIntervalVectorJet),
        budget: inout NativeCurveCurveContactBudget) throws -> [OriginalNativeCurveCurveCriticalContact.Contact] {
        let threshold = OutwardScalarInterval.exact(budget.tolerance.distance)
            * .exact(budget.tolerance.distance)
        let two = try ExactRationalCoefficient.natural(2, usage: &budget)
        let widthU = try ExactRationalCoefficient.originalDouble(domain.u.upper, usage: &budget)
            .subtracting(.originalDouble(domain.u.lower, usage: &budget), usage: &budget)
        let widthV = try ExactRationalCoefficient.originalDouble(domain.v.upper, usage: &budget)
            .subtracting(.originalDouble(domain.v.lower, usage: &budget), usage: &budget)
        func squared(_ value: OutwardScalarInterval) -> OutwardScalarInterval {
            .init(lower: max(0, (value.absoluteLowerBound * value.absoluteLowerBound).nextDown),
                upper: (value.absoluteUpperBound * value.absoluteUpperBound).nextUp)
        }
        try RationalAlgebraStorage.retain(roots.count,
            of: OriginalNativeCurveCurveCriticalContact.Contact.self, usage: &budget)
        var contacts: [OriginalNativeCurveCurveCriticalContact.Contact] = []
        contacts.reserveCapacity(roots.count)
        for original in roots {
            var root = original, targetU = widthU, targetV = widthV
            while true {
                let parameters = try root.enclosure(usage: &budget)
                let (a, b) = try selectedJets(parameters.u, parameters.v, &budget)
                let distance = squared(a.x.value - b.x.value) + squared(a.y.value - b.y.value)
                    + squared(a.z.value - b.z.value)
                if distance.lower > threshold.upper { break }
                if distance.upper <= threshold.lower {
                    let position = try CoordinateEnclosure3D(
                        x: ScalarInterval(lower: a.x.value.lower, upper: a.x.value.upper),
                        y: ScalarInterval(lower: a.y.value.lower, upper: a.y.value.upper),
                        z: ScalarInterval(lower: a.z.value.lower, upper: a.z.value.upper))
                    contacts.append(.init(first: parameters.u, second: parameters.v,
                        axes: axes, position: position, parameterAuthority: .init(root)))
                    break
                }
                guard parameters.u.width > 0 || parameters.v.width > 0 else { throw budget.exhausted() }
                targetU = try targetU.divided(by: two, usage: &budget)
                targetV = try targetV.divided(by: two, usage: &budget)
                root = try root.refined(maximumUWidth: targetU, maximumVWidth: targetV,
                    maximumDepth: maximumDepth, usage: &budget)
            }
        }
        return contacts
    }
}

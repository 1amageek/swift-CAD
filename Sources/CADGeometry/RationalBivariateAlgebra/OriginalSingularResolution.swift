import CADCore

/// Complete real point-blowup resolution retaining original maps and all tangent roots.
package struct OriginalSingularResolution: Sendable {
    package struct Step: Sendable {
        package enum Direction: Sendable { case finite(OriginalSingularFieldRoot), vertical }
        package let direction: Direction
        package let tangentValue: OriginalSingularFieldElement?
        package let removedExceptionalOrder: Int
        package let sourceDepth: Int
    }
    package struct Germ: Sendable {
        package let strictTransform: OriginalSingularFieldPlanePolynomial
        package let originalU: OriginalSingularFieldPlanePolynomial
        package let originalV: OriginalSingularFieldPlanePolynomial
        package let steps: [Step]
        package let freeAlongU: Bool
        package let depth: Int
    }
    package struct IsolatedGerm: Sendable {
        package let strictTransform: OriginalSingularFieldPlanePolynomial
        package let originalU: OriginalSingularFieldPlanePolynomial
        package let originalV: OriginalSingularFieldPlanePolynomial
        package let steps: [Step]
        package let tangent: OriginalSingularFieldPolynomial
        package let depth: Int
    }
    private struct Pending {
        let strictTransform: OriginalSingularFieldPlanePolynomial
        let originalU: OriginalSingularFieldPlanePolynomial
        let originalV: OriginalSingularFieldPlanePolynomial
        let steps: [Step]
        let depth: Int
    }
    package let original: ExactBivariatePolynomial
    package let originalStation: ExactBivariateSystemRoot
    package let germs: [Germ]
    package let isolatedGerms: [IsolatedGerm]

    package init<B: ExactScalarAdmission & ~Copyable>(original: ExactBivariatePolynomial,
        at station: ExactBivariateSystemRoot, maximumDepth: Int, usage: inout B) throws {
        self.original = original; originalStation = station
        let authority = try OriginalRationalZeroSetAuthority(original: original, usage: &usage)
        let local = try OriginalSingularFieldPlanePolynomial.translated(authority.squareFree, at: station,
            maximumDepth: maximumDepth, usage: &usage)
        guard !local.isZero else { throw rationalAlgebraFailure("Original plane law vanishes identically at singular translation.") }
        let base = local.context
        let x = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: true, in: base,
            maximumDepth: maximumDepth, usage: &usage)
        let y = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: false, in: base,
            maximumDepth: maximumDepth, usage: &usage)
        let originalX = try OriginalSingularFieldElement.original(.coordinate(alongU: true, usage: &usage), in: base, usage: &usage)
        let originalY = try OriginalSingularFieldElement.original(.coordinate(alongU: false, usage: &usage), in: base, usage: &usage)
        let mapU = try x.adding(.constant(originalX, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        let mapV = try y.adding(.constant(originalY, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
        let resolved = try Self.resolve(local: local, originalU: mapU, originalV: mapV,
            inheritedDepth: base.depth, maximumDepth: maximumDepth, usage: &usage)
        germs = resolved.germs; isolatedGerms = resolved.isolatedGerms
    }

    static func resolve<B: ExactScalarAdmission & ~Copyable>(local: OriginalSingularFieldPlanePolynomial,
        originalU mapU: OriginalSingularFieldPlanePolynomial, originalV mapV: OriginalSingularFieldPlanePolynomial,
        inheritedDepth: Int, maximumDepth: Int, usage: inout B) throws
        -> (germs: [Germ], isolatedGerms: [IsolatedGerm]) {
        try RationalAlgebraStorage.retain(1, of: Pending.self, usage: &usage)
        var pending = [Pending(strictTransform: local, originalU: mapU, originalV: mapV, steps: [], depth: max(inheritedDepth, local.context.depth))]
        var published: [Germ] = []
        var isolated: [IsolatedGerm] = []
        while let cell = pending.popLast() {
            try usage.visitCell(axis: .value, depth: cell.depth)
            let law = cell.strictTransform
            let oneU = try ExactBivariatePolynomial.Power(u: 1, v: 0)
            let oneV = try ExactBivariatePolynomial.Power(u: 0, v: 1)
            let zero = try ExactBivariatePolynomial.Power(u: 0, v: 0)
            guard law.coefficients[zero] == nil else { throw rationalAlgebraFailure("Original blowup station is not a source zero.") }
            if law.coefficients[oneU] != nil || law.coefficients[oneV] != nil {
                try RationalAlgebraStorage.retain(1, of: Germ.self, usage: &usage)
                published.append(Germ(strictTransform: law, originalU: cell.originalU, originalV: cell.originalV,
                    steps: cell.steps, freeAlongU: law.coefficients[oneV] != nil, depth: cell.depth))
                continue
            }
            guard let order = try law.minimumOrder(usage: &usage), order > 1 else { throw rationalAlgebraFailure("Original singular strict transform has no tangent order.") }
            guard cell.depth < maximumDepth else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
                    message: "Original singular resolution exhausted inherited caller depth.")
            }
            let tangent = try law.tangentPolynomial(alongU: true, maximumDepth: maximumDepth, usage: &usage)
            let roots = try OriginalSingularFieldRoot.allRealRoots(tangent, inheritedDepth: cell.depth,
                maximumDepth: maximumDepth, usage: &usage)
            for root in roots {
                let slope = try root.value(maximumDepth: maximumDepth, usage: &usage)
                let context = slope.context
                let u = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: true, in: context, maximumDepth: maximumDepth, usage: &usage)
                let v = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: false, in: context, maximumDepth: maximumDepth, usage: &usage)
                let moved = try v.adding(.constant(slope, maximumDepth: maximumDepth, usage: &usage), maximumDepth: maximumDepth, usage: &usage)
                let second = try u.multiplied(by: moved, maximumDepth: maximumDepth, usage: &usage)
                pending.append(try Self.child(cell, first: u, second: second, direction: .finite(root), tangentValue: slope,
                    maximumDepth: maximumDepth, usage: &usage))
            }
            let verticalCoefficient = law.coefficients[try .init(u: 0, v: order)]
            if roots.isEmpty, verticalCoefficient != nil {
                try RationalAlgebraStorage.retain(1, of: IsolatedGerm.self, usage: &usage)
                isolated.append(IsolatedGerm(strictTransform: law, originalU: cell.originalU,
                    originalV: cell.originalV, steps: cell.steps, tangent: tangent, depth: cell.depth))
            }
            if verticalCoefficient == nil {
                let u = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: true, in: law.context, maximumDepth: maximumDepth, usage: &usage)
                let v = try OriginalSingularFieldPlanePolynomial.coordinate(alongU: false, in: law.context, maximumDepth: maximumDepth, usage: &usage)
                pending.append(try Self.child(cell, first: u.multiplied(by: v, maximumDepth: maximumDepth, usage: &usage),
                    second: u, direction: .vertical, tangentValue: nil, maximumDepth: maximumDepth, usage: &usage))
            }
        }
        return (published, isolated)
    }

    private static func child<B: ExactScalarAdmission & ~Copyable>(_ parent: Pending,
        first: OriginalSingularFieldPlanePolynomial, second: OriginalSingularFieldPlanePolynomial,
        direction: Step.Direction, tangentValue: OriginalSingularFieldElement?, maximumDepth: Int, usage: inout B) throws -> Pending {
        let law = try parent.strictTransform.embedded(in: first.context, maximumDepth: maximumDepth, usage: &usage)
        let composed = try law.composed(withU: first, v: second, maximumDepth: maximumDepth, usage: &usage)
        let strict = try composed.removingExceptionalPower(alongU: true, maximumDepth: maximumDepth, usage: &usage)
        guard strict.power > 0 else { throw rationalAlgebraFailure("Original blowup has no exceptional source factor.") }
        let depth = max(try rationalAlgebraCount(parent.depth, 1), first.context.depth)
        guard depth <= maximumDepth else { throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
            tolerance: nil, message: "Original tangent extension exceeds causal caller depth.") }
        try usage.visitCell(axis: .value, depth: depth)
        let mapU = try parent.originalU.embedded(in: first.context, maximumDepth: maximumDepth, usage: &usage)
            .composed(withU: first, v: second, maximumDepth: maximumDepth, usage: &usage)
        let mapV = try parent.originalV.embedded(in: first.context, maximumDepth: maximumDepth, usage: &usage)
            .composed(withU: first, v: second, maximumDepth: maximumDepth, usage: &usage)
        try RationalAlgebraStorage.retain(1, of: Pending.self, usage: &usage)
        try RationalAlgebraStorage.retain(rationalAlgebraCount(parent.steps.count, 1), of: Step.self, usage: &usage)
        var steps = parent.steps
        steps.append(Step(direction: direction, tangentValue: tangentValue, removedExceptionalOrder: strict.power, sourceDepth: depth))
        return Pending(strictTransform: strict.polynomial, originalU: mapU, originalV: mapV, steps: steps, depth: depth)
    }
}

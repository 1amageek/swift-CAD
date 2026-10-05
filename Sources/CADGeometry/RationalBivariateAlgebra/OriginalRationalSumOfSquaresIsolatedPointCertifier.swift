/// Exact full polynomial weighted-square identity and original finite zero cover.
package struct OriginalRationalSumOfSquaresIsolatedPointCertifier {
    package static func provesOnlyZero<B: RationalAlgebraAdmitting>(at root: ExactBivariateCriticalPoint,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        guard let originalLeading = root.original.leading else { return false }
        let normalized = originalLeading.value.isPositive ? root.original
            : try root.original.scaled(by: .one.negated, usage: &usage)
        var pending = normalized
        var factors: [ExactBivariatePolynomial] = []
        var identity = ExactBivariatePolynomial.zero
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        while let leading = pending.leading {
            try usage.consumeExactWork(1)
            guard leading.value.isPositive, leading.key.u % 2 == 0, leading.key.v % 2 == 0,
                leading.key.u > 0 || leading.key.v > 0 else { return false }
            let originalPending = pending
            let power = try ExactBivariatePolynomial.Power(u: leading.key.u / 2, v: leading.key.v / 2)
            try usage.retainExactStorage(1)
            var factor = ExactBivariatePolynomial([power: .one])
            var square = try factor.multiplied(by: factor, usage: &usage)
                .scaled(by: leading.value, usage: &usage)
            var remainder = try originalPending.subtracting(square, usage: &usage)
            let twice = try leading.value.multiplied(by: two, usage: &usage)
            while let term = remainder.leading, term.key.u >= power.u, term.key.v >= power.v {
                let nextPower = try ExactBivariatePolynomial.Power(u: term.key.u - power.u, v: term.key.v - power.v)
                guard nextPower.v < power.v || nextPower.v == power.v && nextPower.u < power.u else {
                    throw rationalAlgebraFailure("Original weighted-square completion failed to lower its factor leading monomial.")
                }
                let coefficient = try term.value.divided(by: twice, usage: &usage)
                try usage.retainExactStorage(1)
                factor = try factor.adding(ExactBivariatePolynomial([nextPower: coefficient]), usage: &usage)
                square = try factor.multiplied(by: factor, usage: &usage)
                    .scaled(by: leading.value, usage: &usage)
                let next = try originalPending.subtracting(square, usage: &usage)
                if let nextLeading = next.leading {
                    guard nextLeading.key.v < term.key.v || nextLeading.key.v == term.key.v
                        && nextLeading.key.u < term.key.u else {
                        throw rationalAlgebraFailure("Original weighted-square completion did not lower its remainder.")
                    }
                }
                remainder = next
            }
            guard case .zero = try root.sign(of: factor, maximumDepth: maximumDepth, usage: &usage) else {
                return false
            }
            try usage.retainExactStorage(1); factors.append(factor)
            identity = try identity.adding(square, usage: &usage)
            pending = remainder
        }
        guard !factors.isEmpty, try normalized.subtracting(identity, usage: &usage).isZero else { return false }
        do {
            let roots = try ExactBivariateSystemSolver.isolatedRoots(of: factors,
                over: root.sourceDomain, maximumDepth: maximumDepth, usage: &usage)
            // Each square factor vanishes at the retained original point. The
            // complete finite-system cover therefore contains that point, and
            // a single covered real root proves it is the only zero in the box.
            return roots.count == 1
        } catch ExactBivariateSystemClassification.positiveDimensionalOriginalIdeal(_, _) {
            return false
        }
    }
}

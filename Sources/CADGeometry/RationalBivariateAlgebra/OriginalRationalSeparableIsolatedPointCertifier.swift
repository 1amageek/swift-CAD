import CADCore

/// Whole-rectangle isolated source proof for separable irrational flat stations.
package struct OriginalRationalSeparableIsolatedPointCertifier {
    package static func provesOnlyZero<B: ExactScalarAdmission & ~Copyable>(at root: ExactBivariateCriticalPoint,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        let original = root.original
        for (power, _) in try original.orderedTerms(usage: &usage) {
            if power.u > 0 && power.v > 0 { return false }
        }
        let p = try original.restricted(alongU: false, station: .zero, usage: &usage)
        guard p.uDegree > 0 else { return false }
        let remainder = try ExactBivariateGCD().univariateDivision(p,
            root.projectionRoot.polynomial, usage: &usage).remainder
        guard remainder.uDegree <= 0 else { return false }
        let c = try remainder.evaluated(atU: .zero, v: .zero, usage: &usage)
        let first = try p.subtracting(.constant(c, usage: &usage), usage: &usage)
        let originalConstant = try original.evaluated(atU: .zero, v: .zero, usage: &usage)
        let second = try original.restricted(alongU: true, station: .zero, usage: &usage)
            .subtracting(.constant(originalConstant, usage: &usage), usage: &usage)
            .adding(.constant(c, usage: &usage), usage: &usage)
        // A retained critical receipt owns existence at this actual original
        // pair. No independent extrema sample or approximate minimizer is used.
        guard case .zero = try root.sign(of: first, maximumDepth: maximumDepth, usage: &usage),
              case .zero = try root.sign(of: second.exchangedAxes(usage: &usage),
                maximumDepth: maximumDepth, usage: &usage) else { return false }
        guard let a = try signWithOneZero(first, over: root.sourceDomain.u, usage: &usage),
              let b = try signWithOneZero(second, over: root.sourceDomain.v, usage: &usage) else { return false }
        return a == b
    }

    private static func signWithOneZero<B: ExactScalarAdmission & ~Copyable>(_ source: ExactBivariatePolynomial,
        over interval: ScalarInterval, usage: inout B) throws -> Int? {
        guard source.uDegree > 0, interval.width > 0 else { return nil }
        let lower = try ExactRationalCoefficient.originalDouble(interval.lower, usage: &usage)
        let upper = try ExactRationalCoefficient.originalDouble(interval.upper, usage: &usage)
        let sequence = try ExactUnivariateSturmSequence(source, usage: &usage)
        guard try sequence.count(lower: lower, upper: upper,
            excludesLower: false, excludesUpper: false, usage: &usage) == 1 else { return nil }
        let low = try source.evaluated(atU: lower, v: .zero, usage: &usage)
        let high = try source.evaluated(atU: upper, v: .zero, usage: &usage)
        let a = low.isZero ? 0 : low.isPositive ? 1 : -1
        let b = high.isZero ? 0 : high.isPositive ? 1 : -1
        if a == 0 { return b == 0 ? nil : b }
        if b == 0 { return a }
        return a == b ? a : nil
    }
}

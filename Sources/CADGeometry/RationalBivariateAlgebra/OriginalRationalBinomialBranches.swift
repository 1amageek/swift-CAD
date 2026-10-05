/// Complete real factor locus of an exact translated reducible binomial.
package struct OriginalRationalBinomialBranches: Sendable {
    package let original: ExactBivariatePolynomial
    package let factors: [ExactBivariatePolynomial]
    package let originalPower: Int
    package let reducedUDegree: Int
    package let reducedVDegree: Int
    package let centerU: ExactRationalCoefficient
    package let centerV: ExactRationalCoefficient

    package static func proven<B: RationalAlgebraAdmitting>(original: ExactBivariatePolynomial,
        usage: inout B) throws -> Self? {
        if let native = try axisAligned(original: original, usage: &usage) { return native }
        for chart in try OriginalRationalBinomialChart.candidates(original: original, usage: &usage) {
            guard let inner = try axisAligned(original: chart.transformed, usage: &usage) else { continue }
            try usage.retainExactStorage(inner.factors.count)
            var factors: [ExactBivariatePolynomial] = []
            for factor in inner.factors {
                let pulledBack = try factor.composed(withU: chart.chartU, v: chart.chartV, usage: &usage)
                _ = try original.dividedExactly(by: pulledBack, usage: &usage)
                factors.append(pulledBack)
            }
            return try Self(original: original, factors: factors, originalPower: inner.originalPower,
                reducedUDegree: inner.reducedUDegree, reducedVDegree: inner.reducedVDegree,
                centerU: chart.originalU.evaluated(atU: inner.centerU, v: inner.centerV, usage: &usage),
                centerV: chart.originalV.evaluated(atU: inner.centerU, v: inner.centerV, usage: &usage))
        }
        return nil
    }

    private static func axisAligned<B: RationalAlgebraAdmitting>(original: ExactBivariatePolynomial,
        usage: inout B) throws -> Self? {
        if let native = try separated(original: original, usage: &usage) { return native }
        for chart in try OriginalRationalPolynomialShearChart.candidates(original: original, usage: &usage) {
            guard let inner = try separated(original: chart.transformed, usage: &usage) else { continue }
            try usage.retainExactStorage(inner.factors.count)
            var factors: [ExactBivariatePolynomial] = []
            for factor in inner.factors {
                let pulledBack = try factor.composed(withU: chart.chartU, v: chart.chartV, usage: &usage)
                _ = try original.dividedExactly(by: pulledBack, usage: &usage)
                factors.append(pulledBack)
            }
            return try Self(original: original, factors: factors, originalPower: inner.originalPower,
                reducedUDegree: inner.reducedUDegree, reducedVDegree: inner.reducedVDegree,
                centerU: chart.originalU.evaluated(atU: inner.centerU, v: inner.centerV, usage: &usage),
                centerV: chart.originalV.evaluated(atU: inner.centerU, v: inner.centerV, usage: &usage))
        }
        return nil
    }

    private static func separated<B: RationalAlgebraAdmitting>(original: ExactBivariatePolynomial,
        usage: inout B) throws -> Self? {
        let m = original.uDegree, n = original.vDegree
        guard m >= 2, n >= 2 else { return nil }
        var k = m, remainder = n
        while remainder != 0 {
            try usage.consumeExactWork(1)
            let next = k % remainder; k = remainder; remainder = next
        }
        guard k > 1 else { return nil }
        let terms = try original.orderedTerms(usage: &usage)
        guard terms.allSatisfy({ $0.0.u == 0 || $0.0.v == 0 }) else { return nil }
        func coefficient(_ degree: Int, alongU: Bool) -> ExactRationalCoefficient {
            terms.first(where: { $0.0.u == (alongU ? degree : 0) && $0.0.v == (alongU ? 0 : degree) })?.1 ?? .zero
        }
        let a = coefficient(m, alongU: true), b = coefficient(n, alongU: false)
        let c = try coefficient(m - 1, alongU: true).negated.divided(by:
            a.multiplied(by: .natural(m, usage: &usage), usage: &usage), usage: &usage)
        let d = try coefficient(n - 1, alongU: false).negated.divided(by:
            b.multiplied(by: .natural(n, usage: &usage), usage: &usage), usage: &usage)
        let gain = try b.negated.divided(by: a, usage: &usage)
        guard let h = try gain.exactRealRoot(degree: k, usage: &usage) else { return nil }
        let x = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            .subtracting(.constant(c, usage: &usage), usage: &usage)
        let y = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
            .subtracting(.constant(d, usage: &usage), usage: &usage)
        func power(_ source: ExactBivariatePolynomial, _ degree: Int,
            usage: inout B) throws -> ExactBivariatePolynomial {
            try usage.retainExactStorage(1)
            return try ExactBivariatePolynomial([.init(u: degree, v: 0): .one])
                .composed(withU: source, v: .zero, usage: &usage)
        }
        let reconstructed = try power(x, m, usage: &usage).scaled(by: a, usage: &usage)
            .adding(power(y, n, usage: &usage).scaled(by: b, usage: &usage), usage: &usage)
        guard try original.subtracting(reconstructed, usage: &usage).isZero else { return nil }
        let p = try power(x, m / k, usage: &usage)
        let q = try power(y, n / k, usage: &usage).scaled(by: h, usage: &usage)
        let first = try p.subtracting(q, usage: &usage)
        _ = try original.dividedExactly(by: first, usage: &usage)
        try usage.retainExactStorage(1); var factors = [first]
        if k % 2 == 0 {
            let second = try p.adding(q, usage: &usage)
            _ = try original.dividedExactly(by: second, usage: &usage)
            try usage.retainExactStorage(1); factors.append(second)
        }
        return Self(original: original, factors: factors, originalPower: k,
            reducedUDegree: m / k, reducedVDegree: n / k, centerU: c, centerV: d)
    }
}

/// Exact invertible triangular charts for original two-linear-form binomials.
package struct OriginalRationalBinomialChart: Sendable {
    package let transformed: ExactBivariatePolynomial
    package let originalU: ExactBivariatePolynomial
    package let originalV: ExactBivariatePolynomial
    package let chartU: ExactBivariatePolynomial
    package let chartV: ExactBivariatePolynomial
    package let swapped: Bool

    package static func candidates<B: RationalAlgebraAdmitting>(original: ExactBivariatePolynomial,
        usage: inout B) throws -> [Self] {
        var result: [Self] = []
        for swapped in [false, true] {
            let source = swapped ? try original.exchangedAxes(usage: &usage) : original
            let terms = try source.orderedTerms(usage: &usage)
            var degree = 0
            for (power, _) in terms { degree = max(degree, try rationalAlgebraCount(power.u, power.v)) }
            guard degree >= 3, let lead = terms.first(where: { $0.0.u == degree && $0.0.v == 0 })?.1 else { continue }
            let mixed = terms.first(where: { $0.0.u == degree - 1 && $0.0.v == 1 })?.1 ?? .zero
            let s = try mixed.divided(by: lead.multiplied(by: .natural(degree, usage: &usage), usage: &usage), usage: &usage)
            let x = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            let y = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
            let firstOriginalU = try x.subtracting(y.scaled(by: s, usage: &usage), usage: &usage)
            let first = try source.composed(withU: firstOriginalU, v: y, usage: &usage)
            func append(_ t: ExactRationalCoefficient, usage: inout B) throws {
                let secondOriginalV = try y.subtracting(x.scaled(by: t, usage: &usage), usage: &usage)
                let orientedU = try firstOriginalU.composed(withU: x, v: secondOriginalV, usage: &usage)
                let u = swapped ? secondOriginalV : orientedU
                let v = swapped ? orientedU : secondOriginalV
                let a = try (swapped ? y : x).adding((swapped ? x : y).scaled(by: s, usage: &usage), usage: &usage)
                let b = try (swapped ? x : y).adding(a.scaled(by: t, usage: &usage), usage: &usage)
                let transformed = try original.composed(withU: u, v: v, usage: &usage)
                guard try a.composed(withU: u, v: v, usage: &usage).subtracting(x, usage: &usage).isZero,
                    try b.composed(withU: u, v: v, usage: &usage).subtracting(y, usage: &usage).isZero else {
                    throw rationalAlgebraFailure("Original binomial chart failed exact inverse-coordinate identity.")
                }
                try usage.retainExactStorage(1)
                result.append(Self(transformed: transformed, originalU: u, originalV: v,
                    chartU: a, chartV: b, swapped: swapped))
            }
            if !s.isZero { try append(.zero, usage: &usage) }
            let n = first.vDegree
            guard n >= 2 else { continue }
            let top = try first.coefficient(ofV: n, usage: &usage)
            guard top.uDegree == 0, let leading = top.leading?.value else { continue }
            let firstTerms = try first.orderedTerms(usage: &usage)
            let next = firstTerms.first(where: { $0.0.u == 1 && $0.0.v == n - 1 })?.1 ?? .zero
            let t = try next.divided(by: leading.multiplied(by: .natural(n, usage: &usage), usage: &usage), usage: &usage)
            if !t.isZero { try append(t, usage: &usage) }
        }
        return result
    }
}

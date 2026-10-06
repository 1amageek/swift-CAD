/// Exact original polynomial triangular charts, with their complete inverse maps.
struct OriginalRationalPolynomialShearChart: Sendable {
    let transformed: ExactBivariatePolynomial
    let originalU: ExactBivariatePolynomial
    let originalV: ExactBivariatePolynomial
    let chartU: ExactBivariatePolynomial
    let chartV: ExactBivariatePolynomial
    let swapped: Bool

    static func candidates<B: RationalAlgebraAdmitting>(original: ExactBivariatePolynomial,
        usage: inout B) throws -> [Self] {
        var result: [Self] = []
        for swapped in [false, true] {
            let source = swapped ? try original.exchangedAxes(usage: &usage) : original
            let n = source.vDegree
            guard n >= 2 else { continue }
            let top = try source.coefficient(ofV: n, usage: &usage)
            guard top.uDegree == 0, let a = top.leading?.value else { continue }
            let next = try source.coefficient(ofV: n - 1, usage: &usage)
            guard next.uDegree > 0 else { continue }
            let center = try next.scaled(by: .one.negated.divided(by:
                a.multiplied(by: .natural(n, usage: &usage), usage: &usage), usage: &usage), usage: &usage)
            let x = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            let y = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
            let nativeY = try y.adding(center, usage: &usage)
            let originalU = swapped ? nativeY : x
            let originalV = swapped ? x : nativeY
            let chartU = swapped ? y : x
            let chartV = try (swapped ? x : y).subtracting(center.composed(withU: chartU,
                v: .zero, usage: &usage), usage: &usage)
            let transformed = try original.composed(withU: originalU, v: originalV, usage: &usage)
            guard try chartU.composed(withU: originalU, v: originalV, usage: &usage).subtracting(x, usage: &usage).isZero,
                chartV.composed(withU: originalU, v: originalV, usage: &usage).subtracting(y, usage: &usage).isZero else {
                throw rationalAlgebraFailure("Original polynomial shear failed its exact full inverse-coordinate law.")
            }
            try usage.retainExactStorage(1)
            result.append(Self(transformed: transformed, originalU: originalU, originalV: originalV,
                chartU: chartU, chartV: chartV, swapped: swapped))
        }
        return result
    }
}

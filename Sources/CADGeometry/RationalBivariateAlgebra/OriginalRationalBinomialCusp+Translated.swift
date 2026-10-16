/// Exact translated coprime-binomial parametrization from original coefficient bits.
extension OriginalRationalBinomialCusp {
    static func translatedBinomial<B: ExactScalarAdmission & ~Copyable>(original: ExactBivariatePolynomial,
        usage: inout B) throws -> Self? {
        let m = original.uDegree, n = original.vDegree
        guard m >= 2, n >= 2 else { return nil }
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
        func power(_ source: ExactBivariatePolynomial, _ degree: Int, usage: inout B) throws -> ExactBivariatePolynomial {
            try RationalAlgebraStorage.retain(1, of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self, usage: &usage)
            let term = try ExactBivariatePolynomial([.init(u: degree, v: 0): .one])
            return try term.composed(withU: source, v: .zero, usage: &usage)
        }
        let x = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
            .subtracting(.constant(c, usage: &usage), usage: &usage)
        let y = try ExactBivariatePolynomial.coordinate(alongU: false, usage: &usage)
            .subtracting(.constant(d, usage: &usage), usage: &usage)
        let reconstructed = try power(x, m, usage: &usage).scaled(by: a, usage: &usage)
            .adding(power(y, n, usage: &usage).scaled(by: b, usage: &usage), usage: &usage)
        guard try original.subtracting(reconstructed, usage: &usage).isZero else { return nil }
        var oldR = m, r = n, oldS = 1, s = 0, oldT = 0, t = 1
        while r != 0 {
            try usage.consumeWork(1)
            let quotient = oldR / r
            func next(_ old: Int, _ current: Int) throws -> Int {
                let product = quotient.multipliedReportingOverflow(by: current)
                let value = old.subtractingReportingOverflow(product.partialValue)
                guard !product.overflow, !value.overflow else {
                    throw rationalAlgebraFailure("Original coprime-binomial Bezout coefficients overflow finite index arithmetic.")
                }
                return value.partialValue
            }
            let newR = try next(oldR, r), newS = try next(oldS, s), newT = try next(oldT, t)
            oldR = r; r = newR; oldS = s; s = newS; oldT = t; t = newT
        }
        guard oldR == 1 else { return nil }
        let g = try b.negated.divided(by: a, usage: &usage)
        func rationalPower(_ exponent: Int, usage: inout B) throws -> ExactRationalCoefficient {
            guard exponent != Int.min else { throw rationalAlgebraFailure("Original binomial signed power exceeds finite index arithmetic.") }
            var count = abs(exponent), factor = g, result = ExactRationalCoefficient.one
            while count > 0 {
                try usage.consumeWork(1)
                if count % 2 == 1 { result = try result.multiplied(by: factor, usage: &usage) }
                count /= 2
                if count > 0 { factor = try factor.multiplied(by: factor, usage: &usage) }
            }
            return exponent < 0 ? try .one.divided(by: result, usage: &usage) : result
        }
        guard oldT != Int.min else { throw rationalAlgebraFailure("Original binomial inverse exponent overflows.") }
        let gainU = try rationalPower(oldS, usage: &usage), gainV = try rationalPower(-oldT, usage: &usage)
        try RationalAlgebraStorage.retain(2, of: (ExactBivariatePolynomial.Power, ExactRationalCoefficient).self, usage: &usage)
        let u = try ExactBivariatePolynomial([.init(u: n, v: 0): gainU]).adding(.constant(c, usage: &usage), usage: &usage)
        let v = try ExactBivariatePolynomial([.init(u: m, v: 0): gainV]).adding(.constant(d, usage: &usage), usage: &usage)
        guard try original.composed(withU: u, v: v, usage: &usage).isZero else {
            throw rationalAlgebraFailure("Original coprime-binomial map fails its full source zero identity.")
        }
        return Self(original: original, oddCoordinateAlongU: true,
            characteristicExponent: max(m, n), branchMultiplicity: min(m, n), parameterExponent: n,
            gain: gainU, centerU: c, centerV: d, parameterPowerCoordinate: x, u: u, v: v)
    }
}

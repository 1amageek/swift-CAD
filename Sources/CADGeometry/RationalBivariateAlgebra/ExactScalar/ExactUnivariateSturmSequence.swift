/// An exact original square-free Sturm chain with explicit endpoint conventions.
package struct ExactUnivariateSturmSequence: Sendable {
    package let source: ExactBivariatePolynomial
    package let chain: [ExactBivariatePolynomial]
    package init<B: RationalAlgebraAdmitting>(_ source: ExactBivariatePolynomial, usage: inout B) throws {
        guard !source.isZero, source.vDegree <= 0 else {
            throw exactScalarBackendFailure("Exact Sturm source must be a nonzero univariate polynomial.")
        }
        let gcd = ExactBivariateGCD()
        let derivative = try source.differentiated(alongU: true, usage: &usage)
        let repeated = try gcd.univariateGCD(source, derivative, usage: &usage)
        self.source = try source.dividedExactly(by: repeated, usage: &usage)
        if self.source.uDegree == 0 {
            try RationalAlgebraStorage.retain(1, of: ExactBivariatePolynomial.self, usage: &usage)
            chain = [self.source]; return
        }
        try RationalAlgebraStorage.retain(2, of: ExactBivariatePolynomial.self, usage: &usage)
        var values = [self.source, try self.source.differentiated(alongU: true, usage: &usage)]
        while let last = values.last, !last.isZero {
            let remainder = try gcd.univariateDivision(values[values.count - 2], last, usage: &usage).remainder
            if remainder.isZero { break }
            try RationalAlgebraStorage.retain(1, of: ExactBivariatePolynomial.self, usage: &usage)
            values.append(try remainder.scaled(by: .one.negated, usage: &usage))
        }
        chain = values
    }
    func variations<B: RationalAlgebraAdmitting>(at station: ExactRationalCoefficient,
        usage: inout B) throws -> Int {
        var previous = 0, count = 0
        for value in chain {
            let coefficient = try value.evaluated(atU: station, v: .zero, usage: &usage)
            let sign = coefficient.isPositive ? 1 : coefficient.isNegative ? -1 : 0
            if sign == 0 { continue }
            if previous != 0, previous != sign { count += 1 }
            previous = sign
        }
        return count
    }
    func count<B: RationalAlgebraAdmitting>(lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        excludesLower: Bool, excludesUpper: Bool, usage: inout B) throws -> Int {
        if lower == upper {
            if excludesLower || excludesUpper { return 0 }
            return try source.evaluated(atU: lower, v: .zero, usage: &usage).isZero ? 1 : 0
        }
        var result = try variations(at: lower, usage: &usage) - variations(at: upper, usage: &usage)
        if !excludesLower, try source.evaluated(atU: lower, v: .zero, usage: &usage).isZero { result += 1 }
        if excludesUpper, try source.evaluated(atU: upper, v: .zero, usage: &usage).isZero { result -= 1 }
        guard result >= 0 else { throw exactScalarBackendFailure("Exact Sturm endpoint root count is inconsistent.") }
        return result
    }
}

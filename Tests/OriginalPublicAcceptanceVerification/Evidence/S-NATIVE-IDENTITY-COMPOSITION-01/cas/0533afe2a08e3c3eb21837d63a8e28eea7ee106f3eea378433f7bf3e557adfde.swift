/// Exact Sturm chain over the ordered field of one original algebraic u-root.
struct ExactAlgebraicFiberSturmSequence: Sendable {
    let source: ExactAlgebraicFiberPolynomial
    let chain: [ExactAlgebraicFiberPolynomial]
    init<B: RationalAlgebraAdmitting>(_ polynomial: ExactAlgebraicFiberPolynomial,
        maximumDepth: Int, usage: inout B) throws {
        guard !polynomial.isZero else { throw exactScalarBackendFailure("An identically-zero algebraic fiber is a component, not discrete roots.") }
        let derivative = try polynomial.differentiated(usage: &usage)
        let repeated = try ExactAlgebraicFiberPolynomial.gcd(polynomial, derivative,
            maximumDepth: maximumDepth, usage: &usage)
        let division = try polynomial.divided(by: repeated, maximumDepth: maximumDepth, usage: &usage)
        guard division.remainder.isZero else { throw exactScalarBackendFailure("Exact algebraic fiber GCD does not divide its source.") }
        source = division.quotient
        if source.degree == 0 {
            try RationalAlgebraStorage.retain(1, of: ExactAlgebraicFiberPolynomial.self, usage: &usage)
            chain = [source]; return
        }
        try RationalAlgebraStorage.retain(2, of: ExactAlgebraicFiberPolynomial.self, usage: &usage)
        var values = [source, try source.differentiated(usage: &usage)]
        while let last = values.last, !last.isZero {
            let remainder = try values[values.count - 2].divided(by: last,
                maximumDepth: maximumDepth, usage: &usage).remainder
            if remainder.isZero { break }
            try RationalAlgebraStorage.retain(1, of: ExactAlgebraicFiberPolynomial.self, usage: &usage); values.append(try remainder.negated(usage: &usage))
        }
        chain = values
    }
    private func variations<B: RationalAlgebraAdmitting>(at station: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B) throws -> Int {
        var previous = 0, result = 0
        for polynomial in chain {
            let sign = try polynomial.evaluated(at: station, usage: &usage)
                .sign(at: polynomial.root, maximumDepth: maximumDepth, usage: &usage)
            let current: Int
            switch sign { case .negative: current = -1; case .zero: current = 0; case .positive: current = 1 }
            if current == 0 { continue }
            if previous != 0, current != previous { result += 1 }
            previous = current
        }
        return result
    }
    func count<B: RationalAlgebraAdmitting>(lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        excludesLower: Bool, excludesUpper: Bool, maximumDepth: Int, usage: inout B) throws -> Int {
        func isZero(_ station: ExactRationalCoefficient) throws -> Bool {
            if case .zero = try source.evaluated(at: station, usage: &usage)
                .sign(at: source.root, maximumDepth: maximumDepth, usage: &usage) { return true }
            return false
        }
        if lower == upper {
            if excludesLower || excludesUpper { return 0 }
            return try isZero(lower) ? 1 : 0
        }
        var result = try variations(at: lower, maximumDepth: maximumDepth, usage: &usage)
            - variations(at: upper, maximumDepth: maximumDepth, usage: &usage)
        if !excludesLower, try isZero(lower) { result += 1 }
        if excludesUpper, try isZero(upper) { result -= 1 }
        guard result >= 0 else { throw exactScalarBackendFailure("Exact algebraic fiber endpoint count is inconsistent.") }
        return result
    }
}

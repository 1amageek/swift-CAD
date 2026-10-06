/// Exhaustive real-root counts over one retained original ordered field.
struct OriginalSingularFieldSturm: Sendable {
    let source: OriginalSingularFieldPolynomial
    let chain: [OriginalSingularFieldPolynomial]
    init<B: RationalAlgebraAdmitting>(_ original: OriginalSingularFieldPolynomial,
        maximumDepth: Int, usage: inout B) throws {
        guard !original.isZero else { throw rationalAlgebraFailure("Original tower Sturm law is zero.") }
        let derivative = try original.differentiated(maximumDepth: maximumDepth, usage: &usage)
        let repeated = try OriginalSingularFieldPolynomial.gcd(original, derivative, maximumDepth: maximumDepth, usage: &usage)
        let division = try original.divided(by: repeated, maximumDepth: maximumDepth, usage: &usage)
        guard division.remainder.isZero else { throw rationalAlgebraFailure("Original tower square-free division has a remainder.") }
        source = division.quotient
        if source.degree == 0 { try RationalAlgebraStorage.retain(1, of: OriginalSingularFieldPolynomial.self, usage: &usage); chain = [source]; return }
        let capacity = try rationalAlgebraCount(source.degree, 1)
        try RationalAlgebraStorage.retain(capacity, of: OriginalSingularFieldPolynomial.self, usage: &usage)
        var values: [OriginalSingularFieldPolynomial] = []; values.reserveCapacity(capacity)
        values.append(source); values.append(try source.differentiated(maximumDepth: maximumDepth, usage: &usage))
        while let last = values.last, !last.isZero {
            let remainder = try values[values.count - 2].divided(by: last, maximumDepth: maximumDepth, usage: &usage).remainder
            if remainder.isZero { break }
            values.append(try remainder.negated(maximumDepth: maximumDepth, usage: &usage))
        }
        chain = values
    }
    func sign<B: RationalAlgebraAdmitting>(_ polynomial: OriginalSingularFieldPolynomial,
        at station: ExactRationalCoefficient, maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        let value = try OriginalSingularFieldElement.constant(station, in: polynomial.context, maximumDepth: maximumDepth, usage: &usage)
        return try polynomial.evaluated(at: value, maximumDepth: maximumDepth, usage: &usage)
            .sign(maximumDepth: maximumDepth, usage: &usage)
    }
    func variations<B: RationalAlgebraAdmitting>(at station: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B) throws -> Int {
        let value = try OriginalSingularFieldElement.constant(station, in: source.context,
            maximumDepth: maximumDepth, usage: &usage)
        return try variations(at: value, maximumDepth: maximumDepth, usage: &usage)
    }
    func variations<B: RationalAlgebraAdmitting>(at station: OriginalSingularFieldElement,
        maximumDepth: Int, usage: inout B) throws -> Int {
        guard station.context === source.context else {
            throw rationalAlgebraFailure("Original Sturm station has a foreign ordered-field owner.")
        }
        var previous = 0, changes = 0
        for polynomial in chain {
            let direction: Int
            switch try polynomial.evaluated(at: station, maximumDepth: maximumDepth, usage: &usage)
                .sign(maximumDepth: maximumDepth, usage: &usage) {
            case .zero: continue
            case .negative: direction = -1
            case .positive: direction = 1
            }
            if previous != 0, previous != direction { changes += 1 }; previous = direction
        }
        return changes
    }
    func count<B: RationalAlgebraAdmitting>(lower: ExactRationalCoefficient, upper: ExactRationalCoefficient,
        excludesLower: Bool, excludesUpper: Bool, maximumDepth: Int, usage: inout B) throws -> Int {
        let order = try upper.subtracting(lower, usage: &usage)
        guard !order.isNegative else { throw rationalAlgebraFailure("Original tower root interval is reversed.") }
        if order.isZero {
            if excludesLower || excludesUpper { return 0 }
            if case .zero = try sign(source, at: lower, maximumDepth: maximumDepth, usage: &usage) { return 1 }
            return 0
        }
        var result = try variations(at: lower, maximumDepth: maximumDepth, usage: &usage)
            - variations(at: upper, maximumDepth: maximumDepth, usage: &usage)
        if !excludesLower, case .zero = try sign(source, at: lower, maximumDepth: maximumDepth, usage: &usage) { result += 1 }
        if excludesUpper, case .zero = try sign(source, at: upper, maximumDepth: maximumDepth, usage: &usage) { result -= 1 }
        guard result >= 0 else { throw rationalAlgebraFailure("Original tower Sturm root count is inconsistent.") }
        return result
    }
}

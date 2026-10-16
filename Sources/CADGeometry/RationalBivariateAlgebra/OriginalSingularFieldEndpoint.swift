/// Exact authored or selected algebraic local parameter endpoint in one source field.
package enum OriginalSingularFieldEndpoint: Sendable {
    case authored(ExactRationalCoefficient)
    case algebraic(OriginalSingularFieldRoot)
    package var lower: ExactRationalCoefficient { switch self { case .authored(let a): a; case .algebraic(let a): a.isolation.lower } }
    package var upper: ExactRationalCoefficient { switch self { case .authored(let a): a; case .algebraic(let a): a.isolation.upper } }
    package var depth: Int { switch self { case .authored: 0; case .algebraic(let a): a.isolation.depth } }

    package func sign<B: ExactScalarAdmission & ~Copyable>(of polynomial: OriginalSingularFieldPolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        switch self {
        case .algebraic(let root): return try root.sign(of: polynomial, maximumDepth: maximumDepth, usage: &usage)
        case .authored(let value):
            let station = try OriginalSingularFieldElement.constant(value, in: polynomial.context,
                maximumDepth: maximumDepth, usage: &usage)
            return try polynomial.evaluated(at: station, maximumDepth: maximumDepth, usage: &usage)
                .sign(maximumDepth: maximumDepth, usage: &usage)
        }
    }

    package static func compare<B: ExactScalarAdmission & ~Copyable>(_ first: inout Self, _ second: inout Self,
        maximumDepth: Int, usage: inout B) throws -> Int {
        switch (first, second) {
        case (.authored(let a), .authored(let b)):
            let difference = try a.subtracting(b, usage: &usage)
            return difference.isPositive ? 1 : difference.isNegative ? -1 : 0
        case (.authored(let a), .algebraic(let b)):
            return -(try sign(b, minus: a, maximumDepth: maximumDepth, usage: &usage))
        case (.algebraic(let a), .authored(let b)):
            return try sign(a, minus: b, maximumDepth: maximumDepth, usage: &usage)
        case (.algebraic(let a), .algebraic(let b)):
            guard a.polynomial.context === b.polynomial.context else { throw rationalAlgebraFailure("Original local endpoints have unrelated parent fields.") }
            let common = try OriginalSingularFieldPolynomial.gcd(a.polynomial, b.polynomial,
                maximumDepth: maximumDepth, usage: &usage)
            var x = a, y = b
            while true {
                if try x.isolation.lower.subtracting(y.isolation.upper, usage: &usage).isPositive {
                    first = .algebraic(x); second = .algebraic(y); return 1
                }
                if try y.isolation.lower.subtracting(x.isolation.upper, usage: &usage).isPositive {
                    first = .algebraic(x); second = .algebraic(y); return -1
                }
                if common.degree > 0 {
                    let lowerOrder = try x.isolation.lower.subtracting(y.isolation.lower, usage: &usage)
                    let upperOrder = try x.isolation.upper.subtracting(y.isolation.upper, usage: &usage)
                    let lo = lowerOrder.isNegative ? y.isolation.lower : x.isolation.lower
                    let hi = upperOrder.isPositive ? y.isolation.upper : x.isolation.upper
                    let excludesLow = lowerOrder.isPositive ? x.isolation.excludesLower : lowerOrder.isNegative ? y.isolation.excludesLower : x.isolation.excludesLower || y.isolation.excludesLower
                    let excludesHigh = upperOrder.isNegative ? x.isolation.excludesUpper : upperOrder.isPositive ? y.isolation.excludesUpper : x.isolation.excludesUpper || y.isolation.excludesUpper
                    let sequence = try OriginalSingularFieldSturm(common, maximumDepth: maximumDepth, usage: &usage)
                    if try sequence.count(lower: lo, upper: hi, excludesLower: excludesLow,
                        excludesUpper: excludesHigh, maximumDepth: maximumDepth, usage: &usage) == 1 {
                        first = .algebraic(x); second = .algebraic(y); return 0
                    }
                }
                x = try x.refinedOnce(maximumDepth: maximumDepth, usage: &usage)
                y = try y.refinedOnce(maximumDepth: maximumDepth, usage: &usage)
            }
        }
    }
    package static func between<B: ExactScalarAdmission & ~Copyable>(_ lower: inout Self, _ upper: inout Self,
        maximumDepth: Int, usage: inout B) throws -> ExactRationalCoefficient {
        guard try compare(&lower, &upper, maximumDepth: maximumDepth, usage: &usage) < 0 else {
            throw rationalAlgebraFailure("Original local sector has no positive exact parameter width.")
        }
        while !((try upper.lower.subtracting(lower.upper, usage: &usage)).isPositive) {
            if case .algebraic(let root) = lower { lower = .algebraic(try root.refinedOnce(maximumDepth: maximumDepth, usage: &usage)) }
            if case .algebraic(let root) = upper { upper = .algebraic(try root.refinedOnce(maximumDepth: maximumDepth, usage: &usage)) }
        }
        return try lower.upper.adding(upper.lower, usage: &usage).divided(by: .natural(2, usage: &usage), usage: &usage)
    }
    private static func sign<B: ExactScalarAdmission & ~Copyable>(_ root: OriginalSingularFieldRoot,
        minus station: ExactRationalCoefficient, maximumDepth: Int, usage: inout B) throws -> Int {
        let constant = try OriginalSingularFieldElement.constant(station.negated, in: root.polynomial.context, maximumDepth: maximumDepth, usage: &usage)
        let one = try OriginalSingularFieldElement.constant(.one, in: root.polynomial.context, maximumDepth: maximumDepth, usage: &usage)
        let equation = try OriginalSingularFieldPolynomial(context: root.polynomial.context,
            coefficients: [constant, one], maximumDepth: maximumDepth, usage: &usage)
        switch try root.sign(of: equation, maximumDepth: maximumDepth, usage: &usage) { case .zero: return 0
        case .negative: return -1; case .positive: return 1 }
    }
}

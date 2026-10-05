/// Original free-axis endpoint with exact source root or authored station authority.
package enum ExactMonotoneGraphEndpoint: Sendable {
    case authored(ExactRationalCoefficient)
    case algebraic(ExactAlgebraicRealRoot)

    package var lower: ExactRationalCoefficient {
        switch self { case .authored(let value): value; case .algebraic(let value): value.isolation.lower }
    }
    package var upper: ExactRationalCoefficient {
        switch self { case .authored(let value): value; case .algebraic(let value): value.isolation.upper }
    }
    package var depth: Int {
        switch self { case .authored: 0; case .algebraic(let value): value.isolation.isolationDepth }
    }
    package func refined<B: RationalAlgebraAdmitting>(maximumWidth: ExactRationalCoefficient,
        maximumDepth: Int, usage: inout B) throws -> Self {
        switch self {
        case .authored: return self
        case .algebraic(let root): return try .algebraic(root.refined(maximumWidth: maximumWidth,
            maximumDepth: maximumDepth, usage: &usage))
        }
    }
    package func sign<B: RationalAlgebraAdmitting>(of expression: ExactBivariatePolynomial,
        maximumDepth: Int, usage: inout B) throws -> ExactAlgebraicRealRoot.Sign {
        switch self {
        case .authored(let station):
            let value = try expression.evaluated(atU: station, v: .zero, usage: &usage)
            return value.isZero ? .zero : value.isPositive ? .positive : .negative
        case .algebraic(let root): return try root.sign(of: expression, maximumDepth: maximumDepth, usage: &usage)
        }
    }
    package func identityEquals(_ other: Self) -> Bool {
        switch (self, other) {
        case let (.authored(a), .authored(b)): return a == b
        case let (.algebraic(a), .algebraic(b)):
            return a.polynomial == b.polynomial && a.isolation.lower == b.isolation.lower
                && a.isolation.upper == b.isolation.upper
                && a.isolation.excludesLowerEndpoint == b.isolation.excludesLowerEndpoint
                && a.isolation.excludesUpperEndpoint == b.isolation.excludesUpperEndpoint
                && a.isolation.isolationDepth == b.isolation.isolationDepth
        default: return false
        }
    }
    package func hashIdentity(into hasher: inout Hasher) {
        func rational(_ value: ExactRationalCoefficient) {
            hasher.combine(value.canonicalSign); hasher.combine(value.canonicalNumeratorWords)
            hasher.combine(value.canonicalDenominatorWords)
        }
        switch self {
        case .authored(let value): hasher.combine(0); rational(value)
        case .algebraic(let value):
            hasher.combine(1); hasher.combine(value.polynomial.uDegree)
            rational(value.isolation.lower); rational(value.isolation.upper)
            hasher.combine(value.isolation.excludesLowerEndpoint); hasher.combine(value.isolation.excludesUpperEndpoint)
            hasher.combine(value.isolation.isolationDepth)
        }
    }
    package func hasSameValue<B: RationalAlgebraAdmitting>(as other: Self,
        maximumDepth: Int, usage: inout B) throws -> Bool {
        switch (self, other) {
        case let (.authored(a), .authored(b)): return a == b
        case let (.authored(a), .algebraic(b)), let (.algebraic(b), .authored(a)):
            let equation = try ExactBivariatePolynomial.coordinate(alongU: true, usage: &usage)
                .subtracting(.constant(a, usage: &usage), usage: &usage)
            if case .zero = try b.sign(of: equation, maximumDepth: maximumDepth, usage: &usage) { return true }
            return false
        case let (.algebraic(a), .algebraic(b)):
            let lower: ExactRationalCoefficient, upper: ExactRationalCoefficient
            let excludesLower: Bool, excludesUpper: Bool
            let lowerOrder = try a.isolation.lower.subtracting(b.isolation.lower, usage: &usage)
            if lowerOrder.isPositive {
                lower = a.isolation.lower; excludesLower = a.isolation.excludesLowerEndpoint
            } else if lowerOrder.isNegative {
                lower = b.isolation.lower; excludesLower = b.isolation.excludesLowerEndpoint
            } else {
                lower = a.isolation.lower
                excludesLower = a.isolation.excludesLowerEndpoint || b.isolation.excludesLowerEndpoint
            }
            let upperOrder = try a.isolation.upper.subtracting(b.isolation.upper, usage: &usage)
            if upperOrder.isNegative {
                upper = a.isolation.upper; excludesUpper = a.isolation.excludesUpperEndpoint
            } else if upperOrder.isPositive {
                upper = b.isolation.upper; excludesUpper = b.isolation.excludesUpperEndpoint
            } else {
                upper = a.isolation.upper
                excludesUpper = a.isolation.excludesUpperEndpoint || b.isolation.excludesUpperEndpoint
            }
            if try upper.subtracting(lower, usage: &usage).isNegative { return false }
            let common = try ExactBivariateGCD().univariateGCD(a.polynomial, b.polynomial, usage: &usage)
            if common.uDegree <= 0 { return false }
            let sequence = try ExactUnivariateSturmSequence(common, usage: &usage)
            return try sequence.count(lower: lower, upper: upper, excludesLower: excludesLower,
                excludesUpper: excludesUpper, usage: &usage) == 1
        }
    }

}

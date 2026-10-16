/// Exact ordered rational interval for algebraic root refinement.
struct ExactRationalInterval: Sendable {
    let lower: ExactRationalCoefficient
    let upper: ExactRationalCoefficient
    init<B: ExactScalarAdmission & ~Copyable>(_ lower: ExactRationalCoefficient,
        _ upper: ExactRationalCoefficient, usage: inout B) throws {
        guard !(try upper.subtracting(lower, usage: &usage)).isNegative else {
            throw rationalAlgebraFailure("Reversed exact rational interval.")
        }
        self.lower = lower; self.upper = upper
    }
    func adding<B: ExactScalarAdmission & ~Copyable>(_ other: Self, usage: inout B) throws -> Self {
        try Self(lower.adding(other.lower, usage: &usage), upper.adding(other.upper, usage: &usage), usage: &usage)
    }
    func multiplied<B: ExactScalarAdmission & ~Copyable>(by other: Self, usage: inout B) throws -> Self {
        try RationalAlgebraStorage.retain(4, of: ExactRationalCoefficient.self, usage: &usage)
        let values = try [lower.multiplied(by: other.lower, usage: &usage),
            lower.multiplied(by: other.upper, usage: &usage),
            upper.multiplied(by: other.lower, usage: &usage),
            upper.multiplied(by: other.upper, usage: &usage)]
        var low = values[0], high = values[0]
        for value in values.dropFirst() {
            if try value.subtracting(low, usage: &usage).isNegative { low = value }
            if try value.subtracting(high, usage: &usage).isPositive { high = value }
        }
        return try Self(low, high, usage: &usage)
    }
}

extension ExactBivariatePolynomial {
    func exactUnivariateInterval<B: ExactScalarAdmission & ~Copyable>(over interval: ExactRationalInterval,
        usage: inout B) throws -> ExactRationalInterval {
        guard vDegree <= 0 else { throw rationalAlgebraFailure("Exact algebraic sign evaluation needs a univariate source.") }
        var result = try ExactRationalInterval(.zero, .zero, usage: &usage)
        if isZero { return result }
        for degree in (0...uDegree).reversed() {
            try usage.consumeWork(1)
            let coefficient = coefficients[try Power(u: degree, v: 0)] ?? .zero
            result = try result.multiplied(by: interval, usage: &usage)
                .adding(ExactRationalInterval(coefficient, coefficient, usage: &usage), usage: &usage)
        }
        return result
    }
}

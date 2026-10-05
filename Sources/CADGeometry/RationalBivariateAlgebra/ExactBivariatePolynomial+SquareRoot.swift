/// Exact original polynomial square identity under the caller algebra ledger.
extension ExactBivariatePolynomial {
    package func exactSquareRoot<B: RationalAlgebraAdmitting>(usage: inout B) throws -> Self? {
        guard let lead = leading else { return .zero }
        guard lead.key.u % 2 == 0, lead.key.v % 2 == 0,
            let value = try lead.value.exactSquareRoot(usage: &usage) else { return nil }
        let power = try Power(u: lead.key.u / 2, v: lead.key.v / 2)
        try usage.retainExactStorage(1)
        var factor = Self([power: value])
        let two = try ExactRationalCoefficient.natural(2, usage: &usage)
        let divisor = try value.multiplied(by: two, usage: &usage)
        var remainder = try subtracting(factor.multiplied(by: factor, usage: &usage), usage: &usage)
        while let term = remainder.leading {
            try usage.consumeExactWork(1)
            guard term.key.u >= power.u, term.key.v >= power.v else { return nil }
            let nextPower = try Power(u: term.key.u - power.u, v: term.key.v - power.v)
            guard nextPower.v < power.v || nextPower.v == power.v && nextPower.u < power.u else { return nil }
            let coefficient = try term.value.divided(by: divisor, usage: &usage)
            try usage.retainExactStorage(1)
            factor = try factor.adding(Self([nextPower: coefficient]), usage: &usage)
            let next = try subtracting(factor.multiplied(by: factor, usage: &usage), usage: &usage)
            if let nextLeading = next.leading {
                guard nextLeading.key.v < term.key.v || nextLeading.key.v == term.key.v && nextLeading.key.u < term.key.u else {
                    throw rationalAlgebraFailure("Original polynomial square extraction failed to lower its exact remainder.")
                }
            }
            remainder = next
        }
        guard try subtracting(factor.multiplied(by: factor, usage: &usage), usage: &usage).isZero else {
            throw rationalAlgebraFailure("Original polynomial square extraction failed its full coefficient identity.")
        }
        return factor
    }
}

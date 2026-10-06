import CADCore

public extension ExactBivariatePolynomial {
    /// Exact single-divisor division in the same lexicographic monomial order.
    func quotientAndRemainder<B: RationalAlgebraAdmitting>(dividingBy divisor: Self,
        usage: inout B) throws -> (quotient: Self, remainder: Self) {
        guard let divisorLead = divisor.leading else { throw rationalAlgebraFailure("Exact polynomial division by zero.") }
        var pending = self, quotient = Self.zero, remainder = Self.zero
        while let lead = pending.leading {
            try usage.consumeExactWork(1); try usage.retainExactStorage(1)
            let originalTerm = Self([lead.key: lead.value])
            if lead.key.u >= divisorLead.key.u, lead.key.v >= divisorLead.key.v {
                let power = try Power(u: lead.key.u - divisorLead.key.u, v: lead.key.v - divisorLead.key.v)
                let term = Self([power: try lead.value.divided(by: divisorLead.value, usage: &usage)])
                quotient = try quotient.adding(term, usage: &usage)
                pending = try pending.subtracting(divisor.multiplied(by: term, usage: &usage), usage: &usage)
            } else {
                remainder = try remainder.adding(originalTerm, usage: &usage)
                pending = try pending.subtracting(originalTerm, usage: &usage)
            }
            if let next = pending.leading {
                guard next.key.v < lead.key.v || (next.key.v == lead.key.v && next.key.u < lead.key.u) else {
                    throw rationalAlgebraFailure("Exact polynomial division did not decrease its original leading monomial.")
                }
            }
        }
        return (quotient, remainder)
    }

    func dividedExactly<B: RationalAlgebraAdmitting>(by divisor: Self, usage: inout B) throws -> Self {
        let result = try quotientAndRemainder(dividingBy: divisor, usage: &usage)
        guard result.remainder.isZero else { throw rationalAlgebraFailure("Original exact polynomial has a nonzero division remainder.") }
        return result.quotient
    }

    /// Removes only coefficientwise-proved original axis factors; never a tolerance factor.
    func dividedByBoundaryFactor<B: RationalAlgebraAdmitting>(alongU: Bool,
        boundary: ExactRationalCoefficient, usage: inout B) throws -> (quotient: Self, multiplicity: Int) {
        let divisor = try Self.coordinate(alongU: alongU, usage: &usage)
            .subtracting(.constant(boundary, usage: &usage), usage: &usage)
        if isZero { throw rationalAlgebraFailure("The zero polynomial has no finite boundary factor multiplicity.") }
        var result = self, multiplicity = 0
        while !result.isZero {
            let division = try result.quotientAndRemainder(dividingBy: divisor, usage: &usage)
            if !division.remainder.isZero { break }
            result = division.quotient
            multiplicity = try rationalAlgebraCount(multiplicity, 1)
        }
        return (result, multiplicity)
    }
}

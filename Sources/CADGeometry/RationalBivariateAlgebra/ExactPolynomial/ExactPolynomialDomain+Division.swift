#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain: ExactPolynomialDividing {
    public typealias Division = ExactPolynomialDivision<F>
    func divided<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, _ divisor: borrowing Polynomial,
        _ usage: inout A) throws -> Division {
        guard let divisorLead = divisor.terms.first else { throw ExactPolynomialFailure.zeroDivisor }
        var pending = copy value, quotient = try wrap([], &usage), remainder = try wrap([], &usage)
        while let lead = pending.terms.first {
            try usage.consumeWork(try ExactPolynomialAccess.count(variableCount, 1))
            let divides = lead.powers.indices.allSatisfy { lead.powers[$0] >= divisorLead.powers[$0] }
            let next: Polynomial
            if divides {
                var exponent = try powers(&usage)
                for i in exponent.indices { exponent[i] = lead.powers[i] - divisorLead.powers[i] }
                let coefficient = try field.dividing(lead.coefficient, divisorLead.coefficient, using: &usage)
                try ExactPolynomialAccess.storage(1, ExactPolynomialTerm<Coefficient>.self, &usage)
                let term = try wrap([.init(powers: exponent, coefficient: coefficient)], &usage)
                quotient = try adding(quotient, term, &usage)
                next = try subtracting(pending, multiplying(divisor, term, &usage), &usage)
            } else {
                try ExactPolynomialAccess.storage(1, ExactPolynomialTerm<Coefficient>.self, &usage)
                let term = try wrap([lead], &usage)
                remainder = try adding(remainder, term, &usage)
                next = try subtracting(pending, term, &usage)
            }
            if let following = next.terms.first {
                guard try ExactPolynomialAccess.order(following.powers, lead.powers, &usage) < 0 else {
                    throw ExactPolynomialFailure.invalidCertificate
                }
            }
            pending = next
        }
        return Division(quotient: try wrap(quotient.terms, &usage), remainder: try wrap(remainder.terms, &usage))
    }
    func exactDivide<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, _ divisor: borrowing Polynomial,
        _ usage: inout A) throws -> Polynomial {
        let result = try divided(value, divisor, &usage)
        guard result.remainder.terms.isEmpty else { throw ExactPolynomialFailure.notDivisible }
        return result.quotient
    }
    func monic<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        _ usage: inout A) throws -> Polynomial {
        guard let lead = value.terms.first else { return try wrap([], &usage) }
        return try scaled(value, field.dividing(context.one, lead.coefficient, using: &usage), &usage)
    }
    public func divided<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, by divisor: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> Division {
        try query(&admission, copy value, copy divisor) { try divided(copy value, copy divisor, &$0) }
    }
    public func dividedExactly<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, by divisor: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission, copy value, copy divisor) { try exactDivide(copy value, copy divisor, &$0) }
    }
    public func normalized<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission, copy value) { try monic(copy value, &$0) }
    }
}

#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain {
    func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        let count = try ExactPolynomialAccess.count(lhs.terms.count, rhs.terms.count)
        try usage.consumeWork(count); try ExactPolynomialAccess.storage(count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var terms = lhs.terms; terms.reserveCapacity(count); terms.append(contentsOf: rhs.terms)
        return try canonical(terms, &usage)
    }
    func negated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        try ExactPolynomialAccess.storage(value.terms.count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var terms: [ExactPolynomialTerm<Coefficient>] = []; terms.reserveCapacity(value.terms.count)
        for term in value.terms { try usage.consumeWork(1); terms.append(.init(powers: term.powers,
            coefficient: try field.negated(term.coefficient, using: &usage))) }
        return try wrap(terms, &usage)
    }
    func subtracting<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        try adding(lhs, negated(rhs, &usage), &usage)
    }
    func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        if lhs.terms.isEmpty || rhs.terms.isEmpty { return try wrap([], &usage) }
        let count = try ExactPolynomialAccess.count(lhs.terms.count, rhs.terms.count, multiply: true)
        try ExactPolynomialAccess.storage(count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var terms: [ExactPolynomialTerm<Coefficient>] = []; terms.reserveCapacity(count)
        for a in lhs.terms { for b in rhs.terms {
            var exponent = try powers(&usage)
            for i in exponent.indices { exponent[i] = try ExactPolynomialAccess.exponent(a.powers[i], b.powers[i]) }
            terms.append(.init(powers: exponent, coefficient: try field.multiplying(a.coefficient, b.coefficient, using: &usage)))
        } }
        return try canonical(terms, &usage)
    }
    func scaled<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, _ coefficient: borrowing Coefficient,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        _ = try field.sign(of: coefficient, using: &usage)
        try ExactPolynomialAccess.storage(value.terms.count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var terms: [ExactPolynomialTerm<Coefficient>] = []; terms.reserveCapacity(value.terms.count)
        for term in value.terms { terms.append(.init(powers: term.powers,
            coefficient: try field.multiplying(term.coefficient, coefficient, using: &usage))) }
        return try canonical(terms, &usage)
    }
    func power<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, _ exponent: Int,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        guard exponent >= 0 else { throw ExactPolynomialFailure.invalidExponent }
        var n = exponent, factor = copy value, result = try constant(context.one, &usage)
        while n > 0 {
            try usage.consumeWork(1)
            if n % 2 == 1 { result = try multiplying(result, factor, &usage) }
            n /= 2
            if n > 0 { factor = try multiplying(factor, factor, &usage) }
        }
        return result
    }
    public func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission, copy lhs, copy rhs) { try adding(copy lhs, copy rhs, &$0) }
    }
    public func subtracting<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission, copy lhs, copy rhs) { try subtracting(copy lhs, copy rhs, &$0) }
    }
    public func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission, copy lhs, copy rhs) { try multiplying(copy lhs, copy rhs, &$0) }
    }
    public func negated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission, copy value) { try negated(copy value, &$0) }
    }
    public func scaled<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, by coefficient: borrowing Coefficient,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        let retained = copy coefficient
        return try query(&admission, copy value) { try scaled(copy value, retained, &$0) }
    }
}

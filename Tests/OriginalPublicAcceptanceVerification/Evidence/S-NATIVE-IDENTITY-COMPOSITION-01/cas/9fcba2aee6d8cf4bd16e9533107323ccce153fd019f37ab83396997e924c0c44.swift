#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain {
    func adding<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        try merged(lhs, rhs, subtract: false, &usage)
    }
    func merged<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial,
        subtract: Bool, _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        let count = try ExactPolynomialAccess.count(lhs.terms.count, rhs.terms.count)
        try ExactPolynomialAccess.storage(count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var terms: [ExactPolynomialTerm<Coefficient>] = []; terms.reserveCapacity(count)
        var left = 0, right = 0
        // Issued operands already have unique, nonzero terms in descending order.
        while left < lhs.terms.count || right < rhs.terms.count {
            try usage.consumeWork(1)
            let order = left == lhs.terms.count ? -1 : right == rhs.terms.count ? 1
                : try ExactPolynomialAccess.order(lhs.terms[left].powers, rhs.terms[right].powers, &usage)
            if order > 0 { terms.append(lhs.terms[left]); left += 1 }
            else if order < 0 {
                let term = rhs.terms[right]
                let coefficient = try subtract ? field.negated(term.coefficient, using: &usage) : term.coefficient
                terms.append(.init(powers: term.powers, coefficient: coefficient)); right += 1
            } else {
                let l = lhs.terms[left], r = rhs.terms[right]
                let coefficient = try subtract ? field.subtracting(l.coefficient, r.coefficient, using: &usage)
                    : field.adding(l.coefficient, r.coefficient, using: &usage)
                if try field.sign(of: coefficient, using: &usage) != .zero {
                    terms.append(.init(powers: l.powers, coefficient: coefficient))
                }
                left += 1; right += 1
            }
        }
        return try wrap(terms, &usage)
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
        try merged(lhs, rhs, subtract: true, &usage)
    }
    func multiplying<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial, _ rhs: borrowing Polynomial,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        if lhs.terms.isEmpty || rhs.terms.isEmpty { return try wrap([], &usage) }
        if lhs.terms.count > 1 && rhs.terms.count > 1 {
            if let direct = try separatedProduct(lhs, rhs, &usage) { return direct }
            return try heapProduct(lhs, rhs, &usage)
        }
        let count = try ExactPolynomialAccess.count(lhs.terms.count, rhs.terms.count, multiply: true)
        try ExactPolynomialAccess.storage(count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var terms: [ExactPolynomialTerm<Coefficient>] = []; terms.reserveCapacity(count)
        let ordered = lhs.terms.count == 1 || rhs.terms.count == 1
        for a in lhs.terms { for b in rhs.terms {
            var exponent = try powers(&usage)
            for i in exponent.indices { exponent[i] = try ExactPolynomialAccess.exponent(a.powers[i], b.powers[i]) }
            let coefficient = try field.multiplying(a.coefficient, b.coefficient, using: &usage)
            if try !ordered || field.sign(of: coefficient, using: &usage) != .zero {
                terms.append(.init(powers: exponent, coefficient: coefficient))
            }
        } }
        // A fixed monomial translates the canonical exponent order injectively.
        return try ordered ? wrap(terms, &usage) : canonical(terms, &usage)
    }
    func scaled<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, _ coefficient: borrowing Coefficient,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        if try field.sign(of: coefficient, using: &usage) == .zero { return try wrap([], &usage) }
        try ExactPolynomialAccess.storage(value.terms.count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var terms: [ExactPolynomialTerm<Coefficient>] = []; terms.reserveCapacity(value.terms.count)
        for term in value.terms {
            try usage.consumeWork(1)
            let product = try field.multiplying(term.coefficient, coefficient, using: &usage)
            if try field.sign(of: product, using: &usage) != .zero {
                terms.append(.init(powers: term.powers, coefficient: product))
            }
        }
        return try wrap(terms, &usage)
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

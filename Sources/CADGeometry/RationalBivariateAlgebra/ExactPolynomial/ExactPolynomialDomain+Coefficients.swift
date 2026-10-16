#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain {
    func activeVariable<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        _ usage: inout A) throws -> Int? {
        var result: Int? = nil
        for term in value.terms {
            try usage.consumeWork(variableCount)
            for i in term.powers.indices where term.powers[i] != 0 { result = max(result ?? 0, i) }
        }
        return result
    }
    func coefficients<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, _ variable: Int,
        _ usage: inout A) throws -> [ExactPolynomialDegreeCoefficient<F>] {
        try requireVariable(variable)
        typealias Entry = (Int, ExactPolynomialTerm<Coefficient>)
        try ExactPolynomialAccess.storage(ExactPolynomialAccess.count(value.terms.count, 3, multiply: true), Entry.self, &usage)
        var entries: [Entry] = []; entries.reserveCapacity(value.terms.count)
        for term in value.terms {
            try usage.consumeWork(variableCount); try ExactPolynomialAccess.storage(variableCount, Int.self, &usage)
            var powers = term.powers; powers[variable] = 0
            entries.append((term.powers[variable], .init(powers: powers, coefficient: term.coefficient)))
        }
        let sorted = try entries.sorted { first, second in
            try usage.consumeWork(1); return first.0 < second.0
        }
        try ExactPolynomialAccess.storage(value.terms.count, ExactPolynomialDegreeCoefficient<F>.self, &usage)
        try ExactPolynomialAccess.storage(value.terms.count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var result: [ExactPolynomialDegreeCoefficient<F>] = []
        result.reserveCapacity(value.terms.count)
        var start = 0
        while start < sorted.count {
            let degree = sorted[start].0
            var terms: [ExactPolynomialTerm<Coefficient>] = []
            while start < sorted.count && sorted[start].0 == degree {
                try usage.consumeWork(1); terms.append(sorted[start].1); start += 1
            }
            result.append(.init(degree: degree, polynomial: try canonical(terms, &usage)))
        }
        return result
    }
    func coefficient<A: ExactScalarAdmission & ~Copyable>(_ entries: [ExactPolynomialDegreeCoefficient<F>], _ degree: Int,
        _ usage: inout A) throws -> Polynomial {
        for entry in entries { try usage.consumeWork(1); if entry.degree == degree { return entry.polynomial } }
        return try wrap([], &usage)
    }
    func shifted<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, _ variable: Int, _ amount: Int,
        _ usage: inout A) throws -> Polynomial {
        try ExactPolynomialAccess.storage(value.terms.count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var terms: [ExactPolynomialTerm<Coefficient>] = []; terms.reserveCapacity(value.terms.count)
        for term in value.terms {
            try usage.consumeWork(variableCount); try ExactPolynomialAccess.storage(variableCount, Int.self, &usage)
            var powers = term.powers; powers[variable] = try ExactPolynomialAccess.exponent(powers[variable], amount)
            terms.append(.init(powers: powers, coefficient: term.coefficient))
        }
        return try wrap(terms, &usage)
    }
    func pseudoRemainder<A: ExactScalarAdmission & ~Copyable>(_ first: borrowing Polynomial,
        _ second: borrowing Polynomial, _ variable: Int, _ usage: inout A) throws -> Polynomial {
        guard let divisorDegree = try degree(second, variable, &usage) else { throw ExactPolynomialFailure.zeroDivisor }
        let divisorEntries = try coefficients(second, variable, &usage)
        let leading = try coefficient(divisorEntries, divisorDegree, &usage)
        var remainder = copy first
        while let originalDegree = try degree(remainder, variable, &usage), originalDegree >= divisorDegree {
            let numeratorEntries = try coefficients(remainder, variable, &usage)
            let originalLeading = try coefficient(numeratorEntries, originalDegree, &usage)
            let next = try subtracting(multiplying(remainder, leading, &usage),
                shifted(multiplying(second, originalLeading, &usage), variable, originalDegree - divisorDegree, &usage), &usage)
            if let nextDegree = try degree(next, variable, &usage) {
                guard nextDegree < originalDegree else { throw ExactPolynomialFailure.invalidCertificate }
            }
            remainder = next
        }
        return try wrap(remainder.terms, &usage)
    }
}

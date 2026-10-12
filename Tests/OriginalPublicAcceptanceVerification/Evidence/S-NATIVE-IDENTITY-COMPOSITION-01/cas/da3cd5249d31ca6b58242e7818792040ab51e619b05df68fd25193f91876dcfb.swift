#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain {
    func scalarPower<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Coefficient, _ exponent: Int,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Coefficient {
        var n = exponent, result = context.one, factor = copy value
        while n > 0 {
            try usage.consumeWork(1)
            if n % 2 == 1 { result = try field.multiplying(result, factor, using: &usage) }
            n /= 2
            if n > 0 { factor = try field.multiplying(factor, factor, using: &usage) }
        }
        return result
    }
    public func evaluated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, at coordinates: [Coefficient],
        using admission: inout A) throws(ExactPolynomialFailure) -> Evaluation {
        try query(&admission, copy value) { usage in
            guard coordinates.count == variableCount else { throw ExactPolynomialFailure.invalidVariableCount }
            for coordinate in coordinates { _ = try field.sign(of: coordinate, using: &usage) }
            var result = context.zero
            for term in value.terms {
                var product = term.coefficient
                for i in term.powers.indices {
                    try usage.consumeWork(1)
                    if term.powers[i] > 0 { product = try field.multiplying(product,
                        scalarPower(coordinates[i], term.powers[i], &usage), using: &usage) }
                }
                result = try field.adding(result, product, using: &usage)
            }
            return Evaluation(context: context, value: result, depth: try usage.depth)
        }
    }
    func differentiated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, _ variable: Int,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial {
        try requireVariable(variable)
        try ExactPolynomialAccess.storage(value.terms.count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var terms: [ExactPolynomialTerm<Coefficient>] = []; terms.reserveCapacity(value.terms.count)
        for term in value.terms {
            try usage.consumeWork(1)
            let exponent = term.powers[variable]
            if exponent == 0 { continue }
            try ExactPolynomialAccess.storage(variableCount, Int.self, &usage)
            try usage.consumeWork(variableCount)
            var powers = term.powers; powers[variable] -= 1
            terms.append(.init(powers: powers, coefficient: try field.multiplying(term.coefficient,
                field.integer(exponent, using: &usage), using: &usage)))
        }
        return try canonical(terms, &usage)
    }
    public func differentiated<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, in variable: Int,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission, copy value) { try differentiated(copy value, variable, &$0) }
    }
    public func substituted<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial, with replacements: [Polynomial],
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial {
        try query(&admission, copy value) { usage in
            guard replacements.count == variableCount else { throw ExactPolynomialFailure.invalidVariableCount }
            for replacement in replacements {
                try usage.consumeWork(1); try require(replacement)
                try usage.admitDepth(value: replacement.depth.value, coefficient: replacement.depth.coefficient)
            }
            var result = try wrap([], &usage)
            for term in value.terms {
                var product = try constant(term.coefficient, &usage)
                for i in term.powers.indices {
                    try usage.consumeWork(1)
                    if term.powers[i] > 0 { product = try multiplying(product, power(replacements[i], term.powers[i], &usage), &usage) }
                }
                result = try adding(result, product, &usage)
            }
            return try wrap(result.terms, &usage)
        }
    }
    /// Transfers coefficients explicitly; unrelated variable counts are not silently reindexed.
    public func importing<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing Polynomial,
        using admission: inout A) throws(ExactPolynomialFailure) -> Polynomial
        where F: ExactScalarImporting, F.Source == F.Value {
        try query(&admission) { usage in
            guard source.variableCount == variableCount else { throw ExactPolynomialFailure.invalidVariableCount }
            try usage.admitDepth(value: source.depth.value, coefficient: source.depth.coefficient)
            if source.context === context { return try wrap(source.terms, &usage) }
            try ExactPolynomialAccess.storage(source.terms.count, ExactPolynomialTerm<Coefficient>.self, &usage)
            var terms: [ExactPolynomialTerm<Coefficient>] = []; terms.reserveCapacity(source.terms.count)
            for term in source.terms {
                terms.append(.init(powers: term.powers, coefficient: try field.importing(term.coefficient, using: &usage)))
            }
            return try canonical(terms, &usage)
        }
    }
}

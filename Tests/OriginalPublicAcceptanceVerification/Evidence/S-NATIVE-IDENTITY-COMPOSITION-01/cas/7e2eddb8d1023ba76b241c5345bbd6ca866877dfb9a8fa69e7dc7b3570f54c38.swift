#if L1_ISOLATED_VERIFICATION
import L0
#endif

extension ExactPolynomialDomain {
    func varyingAxes<A: ExactScalarAdmission & ~Copyable>(_ value: borrowing Polynomial,
        _ usage: inout ExactPolynomialAdmission<A>) throws -> (first: Int, last: Int) {
        var first = variableCount, last = -1
        let reference = value.terms[0].powers
        for term in value.terms {
            try usage.consumeWork(try ExactPolynomialAccess.count(variableCount, 1))
            for axis in 0..<variableCount where term.powers[axis] != reference[axis] {
                first = min(first, axis); last = max(last, axis)
            }
        }
        return (first,last)
    }
    func separatedProduct<A: ExactScalarAdmission & ~Copyable>(_ lhs: borrowing Polynomial,
        _ rhs: borrowing Polynomial, _ usage: inout ExactPolynomialAdmission<A>) throws -> Polynomial? {
        let left = try varyingAxes(lhs, &usage), right = try varyingAxes(rhs, &usage)
        let rows: [ExactPolynomialTerm<Coefficient>], columns: [ExactPolynomialTerm<Coefficient>]
        if left.last < right.first { rows = lhs.terms; columns = rhs.terms }
        else if right.last < left.first { rows = rhs.terms; columns = lhs.terms }
        else { return nil }
        let count = try ExactPolynomialAccess.count(rows.count, columns.count, multiply: true)
        try ExactPolynomialAccess.storage(count, ExactPolynomialTerm<Coefficient>.self, &usage)
        var terms: [ExactPolynomialTerm<Coefficient>] = []; terms.reserveCapacity(count)
        // Varying major axes of rows are constant in columns, proving disjoint ordered streams.
        for row in rows { for column in columns {
            var exponent = try powers(&usage)
            for axis in exponent.indices { exponent[axis] = try ExactPolynomialAccess.exponent(row.powers[axis], column.powers[axis]) }
            terms.append(.init(powers: exponent, coefficient: try field.multiplying(row.coefficient, column.coefficient, using: &usage)))
        } }
        return try wrap(terms, &usage)
    }
}

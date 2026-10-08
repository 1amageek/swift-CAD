#if L3_ISOLATED_VERIFICATION
import L0
import L1
import L2
#endif

extension ExactRealCellDomain {
    func isolateRootUnion(_ source: ExactRealRootSource<Field>,
        laws: [ExactRealRootSource<Field>], active: [Int], domain: ExactRealRootDomain<Field>,
        limits: ExactRealRootLimits, using a: inout ExactCellBorrowedAdmission
    ) throws -> ExactRealRootSet<Field> {
        let p = domain.polynomials
        var linear = true
        for index in active {
            try a.consumeWork(1)
            if try p.degree(of: laws[index].original, in: 0, using: &a) != 1 { linear = false; break }
        }
        if !linear {
            let all = try domain.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &a)
            // Preserve the already known small cuts instead of rebuilding a
            // high-degree Sturm chain for their product. L2 verifies completeness.
            try ExactCellAccess.storage(active.count, ExactRealRootSource<Field>.self, &a)
            var factors: [ExactRealRootSource<Field>] = []
            var remaining = source.original
            for index in active {
                try a.consumeWork(1)
                let factor = try p.greatestCommonDivisor(remaining, laws[index].original, using: &a)
                if let degree = try p.degree(of: factor, in: 0, using: &a), degree > 0 {
                    factors.append(try domain.bind(factor, using: &a))
                    remaining = try p.dividedExactly(remaining, by: factor, using: &a)
                }
                if try p.degree(of: remaining, in: 0, using: &a) == 0 { break }
            }
            let count = try domain.count(source, in: all, factoredBy: factors, using: &a)
            return try domain.isolate(count, limits: limits, using: &a)
        }
        try ExactCellAccess.storage(active.count, Field.Value.self, &a)
        var candidates: [Field.Value] = []; candidates.reserveCapacity(active.count)
        for index in active {
            let law = laws[index].original
            var constant = try context.field.integer(0, using: &a)
            var leading = constant
            for term in law.terms {
                try a.consumeWork(1)
                if term.powers[0] == 0 { constant = term.coefficient }
                else { leading = term.coefficient }
            }
            // These coefficients can belong to an extended prefix field, so
            // retain its issued coefficient family instead of assuming the base.
            let field = try Field(retaining: leading, using: &a)
            let value = try field.dividing(field.negated(constant, using: &a), leading, using: &a)
            var offset = 0, duplicate = false
            while offset < candidates.count {
                try a.consumeWork(1)
                let order = try field.compare(value, candidates[offset], using: &a)
                if order == .equal { duplicate = true; break }
                if order == .less { break }
                offset += 1
            }
            if !duplicate { candidates.insert(value, at: offset) }
        }
        return try domain.isolate(source, fromSortedExactCandidates: candidates, limits: limits, using: &a)
    }

    /// Retains the distinct root union without growing repeated source factors.
    func adjoiningRootCuts(_ law: Polynomial, to union: Polynomial,
        polynomials p: ExactPolynomialDomain<Field>, using a: inout ExactCellBorrowedAdmission
    ) throws -> Polynomial {
        // Specialization has already proved a positive univariate degree. In
        // characteristic zero, law/gcd(law, law') has exactly its distinct zeros.
        if try p.degree(of: law, in: 0, using: &a) == 1 {
            // A nonzero linear law is already square-free and irreducible over
            // this field. Exact remainder zero proves it is already in the union.
            let division = try p.divided(union, by: law, using: &a)
            if try p.isZero(division.remainder, using: &a) { return union }
            return try p.multiplying(union, law, using: &a)
        }
        let derivative = try p.differentiated(law, in: 0, using: &a)
        let repeated = try p.greatestCommonDivisor(law, derivative, using: &a)
        let radical = try p.dividedExactly(law, by: repeated, using: &a)
        let shared = try p.greatestCommonDivisor(union, radical, using: &a)
        let fresh = try p.dividedExactly(radical, by: shared, using: &a)
        // Exact division certifies that every removed factor already belongs to
        // the union. Source laws and their multiplicity/Thom evidence are retained.
        return try p.multiplying(union, fresh, using: &a)
    }
}

#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactRealRootDomain {
    func counted(_ source: ExactRealRootSource<F>, _ domain: ExactRealRootInterval<F.Value>,
        _ a: inout ExactRootBorrowedAdmission) throws -> ExactRealRootCount<F> {
        try require(source, &a); try ExactRootAccess.admit(domain.depth, &a)
        // Revalidate endpoints in this field even when another issuer created the domain.
        if case .finite(let bound) = domain.lower { _ = try context.field.sign(of: bound, using: &a) }
        if case .finite(let bound) = domain.upper { _ = try context.field.sign(of: bound, using: &a) }
        if !domain.isEmpty { _ = try interval(domain.lower, domain.upper, domain.includesLower, domain.includesUpper, &a) }
        let zero = try context.univariate.isZero(source.law, using: &a)
        if domain.isEmpty || zero {
            return ExactRealRootCount(source: source, domain: domain,
                classification: domain.isEmpty ? .finite(distinct: 0, totalMultiplicity: 0) : .wholeDomain,
                factors: [], depth: a.depth)
        }
        let decomposition = try context.univariate.squareFreeDecomposition(source.law, using: &a)
        try ExactRootAccess.admit(decomposition.depth, &a)
        try ExactRootAccess.storage(decomposition.factors.count, (proof: ExactRootSturm<F>, multiplicity: Int).self, &a)
        var factors: [(proof: ExactRootSturm<F>, multiplicity: Int)] = []
        factors.reserveCapacity(decomposition.factors.count)
        var distinct = 0, total = 0
        for factor in decomposition.factors {
            let proof = try sturm(factor.polynomial, &a)
            let n = try roots(proof, domain, &a)
            distinct = try ExactRootAccess.add(distinct, n)
            total = try ExactRootAccess.add(total, ExactRootAccess.multiply(n, factor.multiplicity))
            factors.append((proof, factor.multiplicity))
        }
        return ExactRealRootCount(source: source, domain: domain,
            classification: .finite(distinct: distinct, totalMultiplicity: total), factors: factors, depth: a.depth)
    }
    public func count<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealRootSource<F>,
        in domain: ExactRealRootInterval<F.Value>, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootCount<F> {
        try ExactRootAccess.run(&admission, inherited: context.depth) { try counted(copy source, domain, &$0) }
    }
    public func isolate<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealRootSource<F>,
        in domain: ExactRealRootInterval<F.Value>, limits: ExactRealRootLimits, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSet<F> {
        try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            let count = try counted(copy source, domain, &a)
            guard case .finite(let expected, let total) = count.classification else {
                return ExactRealRootSet(count: count, roots: [], depth: a.depth)
            }
            guard expected <= limits.maximumRoots else { throw ExactRealRootFailure.resultLimit }
            try ExactRootAccess.storage(expected, ExactRealRoot<F>.self, &a)
            var result: [ExactRealRoot<F>] = []; result.reserveCapacity(expected)
            if expected == 0 { return ExactRealRootSet(count: count, roots: result, depth: a.depth) }
            let originalProof = try sturm(source.law, &a)
            for entry in count.factors {
                let initial = try finite(domain, proof: entry.proof, &a)
                try ExactRootAccess.storage(1, ExactRealRootInterval<F.Value>.self, &a)
                var pending = [initial]
                while let cell = pending.popLast() {
                    try a.consumeWork(1)
                    let n = try roots(entry.proof, cell, &a)
                    if n == 0 { continue }
                    if n == 1 {
                        var isolated = cell
                        // The full source law certifies that other factors are excluded too.
                        while try roots(originalProof, isolated, &a) != 1 {
                            isolated = try contracted(entry.proof, isolated, axis: source.refinementAxis, &a)
                        }
                        let before = try interval(.negativeInfinity, isolated.lower, false, !isolated.includesLower, &a)
                        let ordinal = try roots(originalProof, before, &a)
                        guard result.count < expected else { throw ExactRealRootFailure.invalidEvidence }
                        result.append(ExactRealRoot(source: copy source, multiplicity: entry.multiplicity, ordinal: ordinal,
                            isolation: isolated, proof: entry.proof, depth: a.depth))
                    } else {
                        let cells = try split(cell, axis: source.refinementAxis, &a)
                        try ExactRootAccess.storage(2, ExactRealRootInterval<F.Value>.self, &a)
                        pending.append(cells.1); pending.append(cells.0)
                    }
                }
            }
            // Ordinals are globally certified by the full source, so sorting needs no approximate comparator.
            try ExactRootAccess.storage(result.count, ExactRealRoot<F>.self, &a)
            // This buffer has one owner; sort in place and admit its sorting workspace above.
            try result.sort { l, r in try a.consumeWork(1); return l.ordinal < r.ordinal }
            var observed = 0, previous: Int? = nil
            for root in result {
                try a.consumeWork(1)
                guard previous == nil || root.ordinal > previous! else { throw ExactRealRootFailure.invalidEvidence }
                observed = try ExactRootAccess.add(observed, root.multiplicity); previous = root.ordinal
            }
            guard result.count == expected, observed == total else { throw ExactRealRootFailure.invalidEvidence }
            return ExactRealRootSet(count: count, roots: result, depth: a.depth)
        }
    }
    func contracted(_ proof: ExactRootSturm<F>, _ cell: ExactRealRootInterval<F.Value>, axis: ExactScalarRootAxis,
        _ a: inout ExactRootBorrowedAdmission) throws -> ExactRealRootInterval<F.Value> {
        let pair = try split(cell, axis: axis, &a)
        let left = try roots(proof, pair.0, &a)
        if left == 1 { return pair.0 }
        guard left == 0, try roots(proof, pair.1, &a) == 1 else { throw ExactRealRootFailure.invalidEvidence }
        return pair.1
    }
}

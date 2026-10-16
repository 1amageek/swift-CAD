#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactRealRootDomain {
    func counted<A: ExactScalarAdmission & ~Copyable>(_ source: ExactRealRootSource<F>, _ domain: ExactRealRootInterval<F.Value>,
        _ a: inout A) throws -> ExactRealRootCount<F> {
        try require(source, &a); try ExactRootAccess.admit(domain.depth, &a)
        // Revalidate endpoints in this field even when another issuer created the domain.
        if case .finite(let bound) = domain.lower { _ = try context.field.sign(of: bound, using: &a) }
        if case .finite(let bound) = domain.upper { _ = try context.field.sign(of: bound, using: &a) }
        if !domain.isEmpty { _ = try interval(domain.lower, domain.upper, domain.includesLower, domain.includesUpper, &a) }
        let zero = try context.univariate.isZero(source.law, using: &a)
        if domain.isEmpty || zero {
            return ExactRealRootCount(source: source, domain: domain,
                classification: domain.isEmpty ? .finite(distinct: 0, totalMultiplicity: 0) : .wholeDomain,
                factors: [], depth: (try a.depth))
        }
        if source.law.variableCount == 1, source.law.termCount == 2 {
            let leading=source.law.terms[0],constant=source.law.terms[1]
            try a.consumeWork(2)
            if leading.powers[0] == 2,constant.powers[0] == 0,
                try context.field.compare(leading.coefficient,context.field.integer(1,using:&a),using:&a) == .equal,
                try context.field.sign(of:constant.coefficient,using:&a) == .negative {
                let x=try context.univariate.variable(0,using:&a)
                let one=try context.univariate.constant(context.field.integer(1,using:&a),using:&a)
                try ExactRootAccess.storage(3,ExactPolynomial<F>.self,&a)
                try ExactRootAccess.owner((ExactPolynomial<F>,[ExactPolynomial<F>],ExactScalarDepth).self,&a)
                let proof=ExactRootSturm(polynomial:source.law,chain:[source.law,x,one],depth:(try a.depth))
                let n=try roots(proof,domain,&a)
                try ExactRootAccess.storage(1,(proof:ExactRootSturm<F>,multiplicity:Int).self,&a)
                return ExactRealRootCount(source:source,domain:domain,classification:.finite(distinct:n,totalMultiplicity:n),
                    factors:[(proof,1)],depth:(try a.depth))
            }
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
            classification: .finite(distinct: distinct, totalMultiplicity: total), factors: factors, depth: (try a.depth))
    }
    public func count<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealRootSource<F>,
        in domain: ExactRealRootInterval<F.Value>, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootCount<F> {
        try ExactRootAccess.run(&admission, inherited: context.depth) { try counted(copy source, domain, &$0) }
    }
    public func isolate<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealRootSource<F>,
        in domain: ExactRealRootInterval<F.Value>, limits: ExactRealRootLimits, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSet<F> {
        let source = copy source
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try isolated(counted(source, domain, &a), limits: limits, &a)
        }
    }
    public func isolate<A: ExactScalarAdmission & ~Copyable>(_ count: borrowing ExactRealRootCount<F>,
        limits: ExactRealRootLimits, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSet<F> {
        let count = copy count
        return try ExactRootAccess.run(&admission, inherited: count.depth) { a in
            try ExactRootAccess.admit(context.depth, &a)
            return try isolated(count, limits: limits, &a)
        }
    }
    func factorRoots<A: ExactScalarAdmission & ~Copyable>(_ count: ExactRealRootCount<F>, in domain: ExactRealRootInterval<F.Value>,
        _ a: inout A) throws -> Int {
        var result = 0
        for entry in count.factors {
            try a.consumeWork(1)
            result = try ExactRootAccess.add(result, roots(entry.proof, domain, &a))
        }
        return result
    }
    func isolated<A: ExactScalarAdmission & ~Copyable>(_ count: ExactRealRootCount<F>, limits: ExactRealRootLimits,
        _ a: inout A) throws -> ExactRealRootSet<F> {
        let source = count.source, domain = count.domain
        try require(source, &a); try ExactRootAccess.admit(count.depth, &a)
        try ExactRootAccess.admit(domain.depth, &a)
        if !domain.isEmpty { _ = try interval(domain.lower, domain.upper, domain.includesLower, domain.includesUpper, &a) }
        for entry in count.factors { try ExactRootAccess.admit(entry.proof.depth, &a) }
        guard case .finite(let expected, let total) = count.classification else {
            return ExactRealRootSet(count: count, roots: [], depth: (try a.depth))
        }
        guard expected <= limits.maximumRoots else { throw ExactRealRootFailure.resultLimit }
        try ExactRootAccess.storage(expected, ExactRealRoot<F>.self, &a)
        var result: [ExactRealRoot<F>] = []; result.reserveCapacity(expected)
        if expected == 0 { return ExactRealRootSet(count: count, roots: result, depth: (try a.depth)) }
        if expected == 1,count.factors.count == 1 {
            let entry=count.factors[0]
            guard total == entry.multiplicity else { throw ExactRealRootFailure.invalidEvidence }
            let isolated=try finite(domain,proof:entry.proof,&a)
            try ExactRootAccess.visit(isolated.depth,axis:source.refinementAxis,&a)
            let before=try interval(.negativeInfinity,isolated.lower,false,!isolated.includesLower,&a)
            let ordinal=try factorRoots(count,in:before,&a)
            result.append(.init(source:source,multiplicity:entry.multiplicity,ordinal:ordinal,
                isolation:isolated,proof:entry.proof,depth:(try a.depth)))
            return ExactRealRootSet(count:count,roots:result,depth:(try a.depth))
        }
        for entry in count.factors {
            let initial = try finite(domain, proof: entry.proof, &a)
            try ExactRootAccess.storage(1, ExactRealRootInterval<F.Value>.self, &a)
            var pending = [initial]
            while let cell = pending.popLast() {
                try ExactRootAccess.visit(cell.depth, axis: source.refinementAxis, &a)
                try a.consumeWork(1)
                let n = try roots(entry.proof, cell, &a)
                if n == 0 { continue }
                if n == 1 {
                    var isolated = cell
                    // Retained disjoint square-free factors certify the entire original source.
                    while try factorRoots(count, in: isolated, &a) != 1 {
                        isolated = try contracted(entry.proof, isolated, axis: source.refinementAxis, &a)
                    }
                    let before = try interval(.negativeInfinity, isolated.lower, false, !isolated.includesLower, &a)
                    let ordinal = try factorRoots(count, in: before, &a)
                    guard result.count < expected else { throw ExactRealRootFailure.invalidEvidence }
                    result.append(.init(source: source, multiplicity: entry.multiplicity, ordinal: ordinal,
                        isolation: isolated, proof: entry.proof, depth: (try a.depth)))
                } else {
                    let cells = try split(cell, axis: source.refinementAxis, &a)
                    try ExactRootAccess.storage(2, ExactRealRootInterval<F.Value>.self, &a)
                    pending.append(cells.1); pending.append(cells.0)
                }
            }
        }
        try ExactRootAccess.storage(result.count, ExactRealRoot<F>.self, &a)
        try result.sort { l, r in try a.consumeWork(1); return l.ordinal < r.ordinal }
        var observed = 0, previous: Int? = nil
        for root in result {
            try a.consumeWork(1)
            guard previous == nil || root.ordinal > previous! else { throw ExactRealRootFailure.invalidEvidence }
            observed = try ExactRootAccess.add(observed, root.multiplicity); previous = root.ordinal
        }
        guard result.count == expected, observed == total else { throw ExactRealRootFailure.invalidEvidence }
        return ExactRealRootSet(count: count, roots: result, depth: (try a.depth))
    }
    func contracted<A: ExactScalarAdmission & ~Copyable>(_ proof: ExactRootSturm<F>, _ cell: ExactRealRootInterval<F.Value>, axis: ExactScalarRootAxis,
        _ a: inout A) throws -> ExactRealRootInterval<F.Value> {
        try ExactRootAccess.visit(cell.depth, axis: axis, &a)
        let pair = try split(cell, axis: axis, &a)
        let left = try roots(proof, pair.0, &a)
        if left == 1 { return pair.0 }
        guard left == 0, try roots(proof, pair.1, &a) == 1 else { throw ExactRealRootFailure.invalidEvidence }
        return pair.1
    }
}

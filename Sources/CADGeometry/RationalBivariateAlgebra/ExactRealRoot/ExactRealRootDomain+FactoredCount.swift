#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactRealRootDomain {
    public func count<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealRootSource<F>,
        in domain: ExactRealRootInterval<F.Value>, factoredBy hints: [ExactRealRootSource<F>],
        using admission: inout A) throws(ExactRealRootFailure) -> ExactRealRootCount<F> {
        let source = copy source
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try require(source, &a); try ExactRootAccess.admit(domain.depth, &a)
            if case .finite(let bound) = domain.lower { _ = try context.field.sign(of: bound, using: &a) }
            if case .finite(let bound) = domain.upper { _ = try context.field.sign(of: bound, using: &a) }
            if !domain.isEmpty { _ = try interval(domain.lower, domain.upper, domain.includesLower, domain.includesUpper, &a) }
            let p = context.univariate
            for hint in hints {
                try a.consumeWork(1); try require(hint, &a)
                guard hint.variable == source.variable else { throw ExactRealRootFailure.invalidVariable }
                guard let degree = try p.degree(of: hint.law, in: 0, using: &a), degree > 0 else {
                    throw ExactRealRootFailure.invalidSource
                }
            }
            // Hints are not authority: exact division and coprimality prove their complete product.
            var residual = source.law
            for index in hints.indices {
                for previous in 0..<index {
                    try a.consumeWork(1)
                    let common = try p.greatestCommonDivisor(hints[previous].law, hints[index].law, using: &a)
                    guard try p.degree(of: common, in: 0, using: &a) == 0 else {
                        throw ExactRealRootFailure.invalidEvidence
                    }
                }
                let division = try p.divided(residual, by: hints[index].law, using: &a)
                guard try p.isZero(division.remainder, using: &a) else {
                    throw ExactRealRootFailure.invalidEvidence
                }
                residual = division.quotient
            }
            guard try p.degree(of: residual, in: 0, using: &a) == 0,
                let constant = residual.terms.first,
                try context.field.sign(of: constant.coefficient, using: &a) != .zero else {
                throw ExactRealRootFailure.invalidEvidence
            }
            try ExactRootAccess.storage(hints.count, ExactRealRootCount<F>.self, &a)
            var counts: [ExactRealRootCount<F>] = []; counts.reserveCapacity(hints.count)
            var distinct = 0, total = 0, payloadCount = 0
            for hint in hints {
                let count = try counted(hint, domain, &a)
                guard case .finite(let roots, let multiplicity) = count.classification else {
                    throw ExactRealRootFailure.invalidEvidence
                }
                distinct = try ExactRootAccess.add(distinct, roots)
                total = try ExactRootAccess.add(total, multiplicity)
                payloadCount = try ExactRootAccess.add(payloadCount, count.factors.count)
                counts.append(count)
            }
            try ExactRootAccess.storage(payloadCount, (proof: ExactRootSturm<F>, multiplicity: Int).self, &a)
            var factors: [(proof: ExactRootSturm<F>, multiplicity: Int)] = []
            factors.reserveCapacity(payloadCount)
            for count in counts {
                for entry in count.factors {
                    try a.consumeWork(1); try ExactRootAccess.admit(entry.proof.depth, &a)
                    factors.append(entry)
                }
            }
            return .init(source: source, domain: domain,
                classification: .finite(distinct: distinct, totalMultiplicity: total), factors: factors, depth: (try a.depth))
        }
    }
}

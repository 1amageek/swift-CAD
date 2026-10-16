#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactRealRootDomain {
    public func isolate<A: ExactScalarAdmission & ~Copyable>(_ source: borrowing ExactRealRootSource<F>,
        fromSortedExactCandidates candidates: [F.Value], limits: ExactRealRootLimits, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRootSet<F> {
        let source = copy source
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try require(source, &a)
            guard candidates.count <= limits.maximumRoots else { throw ExactRealRootFailure.resultLimit }
            guard try !context.univariate.isZero(source.law, using: &a) else {
                throw ExactRealRootFailure.invalidEvidence
            }
            for index in candidates.indices {
                try a.consumeWork(1)
                _ = try context.field.sign(of: candidates[index], using: &a)
                if index > 0, try context.field.compare(candidates[index - 1], candidates[index], using: &a) != .less {
                    throw ExactRealRootFailure.invalidEvidence
                }
            }
            let all = try interval(.negativeInfinity, .positiveInfinity, false, false, &a)
            try ExactRootAccess.storage(candidates.count, ExactRealRoot<F>.self, &a)
            try ExactRootAccess.storage(candidates.count, (proof: ExactRootSturm<F>, multiplicity: Int).self, &a)
            var result: [ExactRealRoot<F>] = []; result.reserveCapacity(candidates.count)
            var factors: [(proof: ExactRootSturm<F>, multiplicity: Int)] = []
            factors.reserveCapacity(candidates.count)
            var remaining = source.law, total = 0
            let one = try context.univariate.constant(context.field.integer(1, using: &a), using: &a)
            let x = try context.univariate.variable(0, using: &a)
            for index in candidates.indices {
                let candidate = candidates[index]
                let singleton = try interval(.finite(candidate), .finite(candidate), true, true, &a)
                try ExactRootAccess.visit(singleton.depth, axis: source.refinementAxis, &a)
                let linear = try context.univariate.subtracting(x,
                    context.univariate.constant(candidate, using: &a), using: &a)
                var multiplicity = 0
                while let degree = try degree(remaining, &a), degree > 0 {
                    try a.consumeWork(1)
                    let division = try context.univariate.divided(remaining, by: linear, using: &a)
                    if try !context.univariate.isZero(division.remainder, using: &a) { break }
                    multiplicity = try ExactRootAccess.add(multiplicity, 1)
                    remaining = division.quotient
                }
                guard multiplicity > 0 else { throw ExactRealRootFailure.invalidEvidence }
                // The monic linear law has derivative one and exactly this singleton zero.
                try ExactRootAccess.storage(2, ExactPolynomial<F>.self, &a)
                try ExactRootAccess.owner((ExactPolynomial<F>, [ExactPolynomial<F>], ExactScalarDepth).self, &a)
                let proof = ExactRootSturm(polynomial: linear, chain: [linear, one], depth: (try a.depth))
                factors.append((proof, multiplicity))
                total = try ExactRootAccess.add(total, multiplicity)
                result.append(.init(source: source, multiplicity: multiplicity, ordinal: index,
                    isolation: singleton, proof: proof, depth: (try a.depth)))
            }
            guard let remainderDegree = try degree(remaining, &a) else {
                throw ExactRealRootFailure.invalidEvidence
            }
            if remainderDegree > 0 {
                try ExactRootAccess.storage(remaining.termCount, ExactPolynomialTerm<F.Value>.self, &a)
                var terms: [ExactPolynomialTerm<F.Value>] = []; terms.reserveCapacity(remaining.termCount)
                for term in remaining.terms {
                    try a.consumeWork(source.original.variableCount)
                    try ExactRootAccess.storage(source.original.variableCount, Int.self, &a)
                    var powers = Array(repeating: 0, count: source.original.variableCount)
                    powers[source.variable] = term.powers[0]
                    terms.append(.init(powers: powers, coefficient: term.coefficient))
                }
                let original = try context.input.polynomial(terms: terms, using: &a)
                let remainderSource = ExactRealRootSource(context: context, original: original,
                    variable: source.variable, refinementAxis: source.refinementAxis, law: remaining, depth: (try a.depth))
                let exclusion = try counted(remainderSource, all, &a)
                guard exclusion.classification == .finite(distinct: 0, totalMultiplicity: 0) else {
                    throw ExactRealRootFailure.invalidEvidence
                }
                try ExactRootAccess.storage(exclusion.factors.count, (proof: ExactRootSturm<F>, multiplicity: Int).self, &a)
                factors.append(contentsOf: exclusion.factors)
            }
            let count = ExactRealRootCount(source: source, domain: all,
                classification: .finite(distinct: candidates.count, totalMultiplicity: total),
                factors: factors, depth: (try a.depth))
            return .init(count: count, roots: result, depth: (try a.depth))
        }
    }
}

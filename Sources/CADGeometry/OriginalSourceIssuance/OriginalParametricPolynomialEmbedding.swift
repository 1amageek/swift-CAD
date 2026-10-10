#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Reindexes source polynomials into one checked target variable layout.
enum OriginalParametricPolynomialEmbedding {
    static func applying<F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting,A: ExactScalarAdmission & ~Copyable>(
        _ polynomial: ExactPolynomial<F>,map: [Int],ring: ExactPolynomialDomain<F>,field: F,
        using a: inout OriginalSourceProofAdmission<A>) throws -> ExactPolynomial<F> where F.Source == F.Value {
        try a.admitDepth(value:polynomial.depth.value,coefficient:polynomial.depth.coefficient)
        guard polynomial.variableCount==map.count else { throw OriginalSourceIssuanceFailure.invalidChart }
        for index in map.indices {
            try a.consumeWork(1)
            guard map[index]>=0,map[index]<ring.variableCount else { throw OriginalSourceIssuanceFailure.invalidChart }
            for prior in 0..<index {
                try a.consumeWork(1)
                guard map[prior] != map[index] else { throw OriginalSourceIssuanceFailure.invalidChart }
            }
        }
        try a.retainStorage(bytes:exactScalarPayloadBytes(count:polynomial.termCount,of:ExactPolynomialTerm<F.Value>.self))
        var terms:[ExactPolynomialTerm<F.Value>]=[];terms.reserveCapacity(polynomial.termCount)
        for term in polynomial.terms {
            try a.consumeWork(1)
            guard term.powers.count==map.count else { throw OriginalSourceIssuanceFailure.invalidChart }
            try a.retainStorage(bytes:exactScalarPayloadBytes(count:ring.variableCount,of:Int.self))
            var powers=[Int](repeating:0,count:ring.variableCount)
            for index in map.indices { try a.consumeWork(1);powers[map[index]]=term.powers[index] }
            terms.append(.init(powers:powers,coefficient:try field.importing(term.coefficient,using:&a)))
        }
        return try ring.polynomial(terms:terms,using:&a)
    }
}

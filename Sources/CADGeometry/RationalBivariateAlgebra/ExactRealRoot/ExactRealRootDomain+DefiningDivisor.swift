#if L2_ISOLATED_VERIFICATION
import L0
import L1
#endif

extension ExactRealRootDomain {
    public func refine<A: ExactScalarAdmission & ~Copyable>(_ root: borrowing ExactRealRoot<F>,
        usingDefiningDivisor divisor: borrowing ExactRealRootSource<F>, using admission: inout A
    ) throws(ExactRealRootFailure) -> ExactRealRoot<F> {
        let root = copy root, divisor = copy divisor
        return try ExactRootAccess.run(&admission, inherited: context.depth) { a in
            try admitted(root, &a); try require(divisor, &a)
            try ExactRootAccess.visit(root.isolation.depth, axis: root.source.refinementAxis, &a)
            guard let degree = try degree(divisor.law, &a), degree > 0 else {
                throw ExactRealRootFailure.invalidEvidence
            }
            let division = try context.univariate.divided(root.proof.polynomial, by: divisor.law, using: &a)
            guard try context.univariate.isZero(division.remainder, using: &a) else {
                throw ExactRealRootFailure.invalidEvidence
            }
            let proof = try sturm(divisor.law, &a)
            guard try roots(proof, root.isolation, &a) == 1 else { throw ExactRealRootFailure.invalidEvidence }
            return .init(source: root.source, multiplicity: root.multiplicity, ordinal: root.ordinal,
                isolation: root.isolation, proof: proof, depth: a.depth)
        }
    }
}

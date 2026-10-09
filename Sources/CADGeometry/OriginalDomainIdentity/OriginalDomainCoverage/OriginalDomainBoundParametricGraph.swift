#if ORIGINAL_DOMAIN_ISOLATED_VERIFICATION
import L0
import L1
import DI0
import SourceIssuer
#endif

/// A selected local source relation; whole requested coverage belongs to its family.
public struct OriginalDomainBoundParametricGraph<S: Sendable, F: ExactScalarArithmetic & ExactScalarOrdering & ExactScalarImporting, E: Sendable>: Sendable {
    public let graph: OriginalParametricGraphReceipt<S,F,E>
    public let request: OriginalParameterSelection<S,F>
    public let depth: ExactScalarDepth
    init(graph: OriginalParametricGraphReceipt<S,F,E>, request: OriginalParameterSelection<S,F>, depth: ExactScalarDepth) {
        self.graph=graph; self.request=request; self.depth=depth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits, using a: inout A) throws(OriginalDomainIdentityFailure) {
        try OriginalDomainAccess.run(&a) { a in
            guard graph.source.sourceDepth <= limits.source.remainingSourceDepth else { throw OriginalDomainIdentityFailure.sourceDepthLimit }
            try request.frame.require(limits,&a)
            try a.admitDepth(value:depth.value,coefficient:depth.coefficient)
        }
    }
}

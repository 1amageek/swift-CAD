#if SOURCE_ISSUED_MAP_ISOLATED_VERIFICATION
import L0
import L1
import L2
import L3
import L4
import L5
import DI0
import DI
import SourceIssuer
#endif

public struct OriginalIssuedGraphPreparation<S: Sendable,E: Sendable>: Sendable {
    public let original: OriginalDomainBoundParametricGraph<S,OriginalExactScalarDomain,E>
    public let graph: ExactParametricGraph<OriginalExactScalarDomain>
    public let field: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>
    public let depth: ExactScalarDepth
    init(original: OriginalDomainBoundParametricGraph<S,OriginalExactScalarDomain,E>, graph: ExactParametricGraph<OriginalExactScalarDomain>, field: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>, depth: ExactScalarDepth) {
        self.original=original;self.graph=graph;self.field=field;self.depth=depth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,using a: inout A) throws(NativeExactRelationFailure) {
        do { try a.checkpoint();try original.admitProof(limits:limits,using:&a);try a.admitDepth(value:depth.value,coefficient:depth.coefficient);try a.checkpoint() }
        catch { throw .preserving(error) }
    }
}

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

/// An exact whole-plane graph, retaining the source-issued basis and selected UV set.
public struct OriginalIssuedPlaneGraph<S: OriginalPlaneSourceReading>: Sendable {
    public typealias Cover = OriginalPrimitiveDomainCover<S,OriginalExactScalarDomain,OriginalPlaneBasisReceipt<S,OriginalExactScalarDomain>>
    public let original: Cover
    public let graph: ExactParametricGraph<OriginalExactScalarDomain>
    public let field: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>
    public let depth: ExactScalarDepth
    init(original: Cover, graph: ExactParametricGraph<OriginalExactScalarDomain>,
        field: ExactAlgebraicScalarDomain<OriginalExactScalarDomain>, depth: ExactScalarDepth) {
        self.original = original; self.graph = graph; self.field = field; self.depth = depth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalDomainIdentityLimits,
        using a: inout A) throws(NativeExactRelationFailure) {
        do {
            try a.checkpoint(); try original.source.require(limits.source)
            guard limits.maximumCharts >= 1 else { throw OriginalDomainIdentityFailure.chartLimit }
            try a.admitDepth(value: depth.value, coefficient: depth.coefficient)
            try a.checkpoint()
        } catch { throw .preserving(error) }
    }
}

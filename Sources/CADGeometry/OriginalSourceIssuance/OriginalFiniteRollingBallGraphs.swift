#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Complete child product with every original auxiliary and guarded preimage retained.
public struct OriginalFiniteRollingBallGraphs<S: OriginalRollingBallChildSourceReading,E: Sendable,C: Sendable>: Sendable {
    public typealias ChildFamily = OriginalCompleteCurveGraphs<S.Child,E,C>
    public typealias Graph = OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,OriginalRollingBallChildGraphEvidence<S,E>>
    public let source: OriginalSourceBinding<S>
    public let center: ChildFamily
    public let first: ChildFamily
    public let second: ChildFamily
    public let graphs: [Graph]
    public let enclosingSupport: [OriginalSourceParameterInterval<OriginalExactScalar>]
    public let proofDepth: ExactScalarDepth
    public var field: OriginalExactScalarDomain { center.field }
    init(source: OriginalSourceBinding<S>,center: ChildFamily,first: ChildFamily,second: ChildFamily,
        graphs: [Graph],support: [OriginalSourceParameterInterval<OriginalExactScalar>],proofDepth: ExactScalarDepth) {
        self.source=source;self.center=center;self.first=first;self.second=second
        self.graphs=graphs;enclosingSupport=support;self.proofDepth=proofDepth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try source.require(limits)
            guard limits.remainingSourceDepth>0 else { throw OriginalSourceIssuanceFailure.sourceDepthLimit }
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            let children=try OriginalSourceIssuanceLimits(remainingSourceDepth:limits.remainingSourceDepth-1)
            try center.admitProof(limits:children,using:&a)
            try first.admitProof(limits:children,using:&a)
            try second.admitProof(limits:children,using:&a)
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}

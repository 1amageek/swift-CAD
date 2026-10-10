#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Sealed complete finite curve family over its independently authored support.
public struct OriginalFiniteCurveGraphs<S: Sendable,E: Sendable,C: Sendable>: Sendable {
    public typealias Graph=OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,E>
    public let source: OriginalSourceBinding<S>
    public let coverage: C
    public let field: OriginalExactScalarDomain
    public let graphs: [Graph]
    public let support: OriginalSourceParameterInterval<OriginalExactScalar>
    public let proofDepth: ExactScalarDepth
    init(source: OriginalSourceBinding<S>,coverage: C,field: OriginalExactScalarDomain,graphs: [Graph],
        support: OriginalSourceParameterInterval<OriginalExactScalar>,proofDepth: ExactScalarDepth) {
        self.source=source;self.coverage=coverage;self.field=field;self.graphs=graphs
        self.support=support;self.proofDepth=proofDepth
    }
}

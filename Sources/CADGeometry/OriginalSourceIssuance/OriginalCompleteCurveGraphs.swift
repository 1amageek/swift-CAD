#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Sealed complete normalized curve enclosure and every original guarded position graph.
public struct OriginalCompleteCurveGraphs<S: Sendable,E: Sendable,C: Sendable>: Sendable {
    public typealias Field = OriginalExactScalarDomain
    public typealias Graph = OriginalParametricGraphReceipt<S,Field,E>
    public let source: OriginalSourceBinding<S>
    public let coverage: C
    public let field: Field
    public let graphs: [Graph]
    public let support: OriginalSourceParameterInterval<Field.Value>
    public let proofDepth: ExactScalarDepth
    init(source: OriginalSourceBinding<S>,coverage: C,field: Field,graphs: [Graph],
        support: OriginalSourceParameterInterval<Field.Value>,proofDepth: ExactScalarDepth) {
        self.source=source;self.coverage=coverage;self.field=field;self.graphs=graphs
        self.support=support;self.proofDepth=proofDepth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint();try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            for graph in graphs {
                try a.consumeWork(1);try graph.source.require(limits)
                try a.admitDepth(value:graph.proofDepth.value,coefficient:graph.proofDepth.coefficient)
            }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}

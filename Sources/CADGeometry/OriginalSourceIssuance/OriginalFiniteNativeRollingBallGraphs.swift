#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Complete normalized parameter enclosure, with guarded position domains per graph.
public struct OriginalFiniteNativeRollingBallGraphs<S: OriginalRollingBallSourceReading>: Sendable {
    public typealias Graph = OriginalParametricGraphReceipt<S, OriginalExactScalarDomain, OriginalRollingBallGraphEvidence<S>>
    public let source: OriginalSourceBinding<S>
    public let center: OriginalFiniteBSplineCharts<S.Child>
    public let first: OriginalFiniteBSplineCharts<S.Child>
    public let second: OriginalFiniteBSplineCharts<S.Child>
    public let graphs: [Graph]
    public let proofDepth: ExactScalarDepth
    public var field: OriginalExactScalarDomain { center.field }
    public var enclosingSupport: [OriginalSourceParameterInterval<OriginalExactScalar>] { support }
    private let support: [OriginalSourceParameterInterval<OriginalExactScalar>]
    init(source: OriginalSourceBinding<S>, center: OriginalFiniteBSplineCharts<S.Child>,
        first: OriginalFiniteBSplineCharts<S.Child>, second: OriginalFiniteBSplineCharts<S.Child>,
        graphs: [Graph], support: [OriginalSourceParameterInterval<OriginalExactScalar>], proofDepth: ExactScalarDepth) {
        self.source = source; self.center = center; self.first = first; self.second = second
        self.graphs = graphs; self.support = support; self.proofDepth = proofDepth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint(); try source.require(limits)
            try a.admitDepth(value: proofDepth.value, coefficient: proofDepth.coefficient)
            for graph in graphs {
                try a.consumeWork(1)
                try graph.evidence.center.admitProof(using: &a)
                try graph.evidence.first.admitProof(using: &a)
                try graph.evidence.second.admitProof(using: &a)
            }
            try a.checkpoint()
        } catch { throw .init(preserving: error) }
    }
}

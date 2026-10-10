#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Complete finite pair cover; the selected position domain remains guarded.
public struct OriginalFiniteNativeSurfaceLiftGraphs<S: OriginalSurfaceLiftSourceReading>: Sendable {
    public typealias Graph = OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,OriginalSurfaceLiftGraphEvidence<S>>
    public let source: OriginalSourceBinding<S>
    public let surface: OriginalFiniteBSplineCharts<S.Surface>
    public let pcurve: OriginalFiniteBSplineCharts<S.Pcurve>
    public let graphs: [Graph]
    public let proofDepth: ExactScalarDepth
    public let enclosingSupport: [OriginalSourceParameterInterval<OriginalExactScalar>]
    public var field: OriginalExactScalarDomain { surface.field }
    init(source: OriginalSourceBinding<S>, surface: OriginalFiniteBSplineCharts<S.Surface>,
        pcurve: OriginalFiniteBSplineCharts<S.Pcurve>, graphs: [Graph],
        support: [OriginalSourceParameterInterval<OriginalExactScalar>], proofDepth: ExactScalarDepth) {
        self.source=source; self.surface=surface; self.pcurve=pcurve
        self.graphs=graphs; enclosingSupport=support; self.proofDepth=proofDepth
    }
    public func admitProof<A: ExactScalarAdmission & ~Copyable>(limits: OriginalSourceIssuanceLimits,
        using a: inout A) throws(OriginalSourceIssuanceFailure) {
        do {
            try a.checkpoint(); try source.require(limits)
            try a.admitDepth(value:proofDepth.value,coefficient:proofDepth.coefficient)
            for graph in graphs {
                try a.consumeWork(1); try graph.evidence.surface.admitProof(using:&a)
                try graph.evidence.pcurve.admitProof(using:&a)
            }
            try a.checkpoint()
        } catch { throw .init(preserving:error) }
    }
}

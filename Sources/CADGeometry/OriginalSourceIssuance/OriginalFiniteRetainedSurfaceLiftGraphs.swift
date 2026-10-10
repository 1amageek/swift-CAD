#if ORIGINAL_SOURCE_ISOLATED_VERIFICATION
import L0
import L1
#endif

/// Complete finite pair cover; the selected position domain remains guarded.
public struct OriginalFiniteRetainedSurfaceLiftGraphs<S: OriginalRetainedPcurveLiftSourceReading>: Sendable {
    public typealias Graph = OriginalParametricGraphReceipt<S,OriginalExactScalarDomain,OriginalSurfaceLiftGraphEvidence<S>>
    public let source: OriginalSourceBinding<S>
    public let surfaceSource: OriginalSourceBinding<S.Surface>
    public let surfaceLaws: [OriginalRationalChartReceipt<S.Surface,S.SurfaceSelection,OriginalExactScalarDomain>]
    public let surfaceSupport: [OriginalSourceParameterInterval<OriginalExactScalar>]
    public let field: OriginalExactScalarDomain
    public let pcurve: OriginalFiniteRetainedCurveCharts<S.Pcurve>
    public let graphs: [Graph]
    public let proofDepth: ExactScalarDepth
    public let enclosingSupport: [OriginalSourceParameterInterval<OriginalExactScalar>]
    init(source: OriginalSourceBinding<S>, surfaceSource: OriginalSourceBinding<S.Surface>,
        surfaceLaws: [OriginalRationalChartReceipt<S.Surface,S.SurfaceSelection,OriginalExactScalarDomain>],
        surfaceSupport: [OriginalSourceParameterInterval<OriginalExactScalar>], field: OriginalExactScalarDomain,
        pcurve: OriginalFiniteRetainedCurveCharts<S.Pcurve>, graphs: [Graph],
        support: [OriginalSourceParameterInterval<OriginalExactScalar>], proofDepth: ExactScalarDepth) {
        self.source=source; self.surfaceSource=surfaceSource; self.surfaceLaws=surfaceLaws
        self.surfaceSupport=surfaceSupport; self.field=field; self.pcurve=pcurve
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

extension OriginalFiniteRetainedSurfaceLiftGraphs where S: OriginalRetainedSurfaceLiftSourceReading {
    /// Typed Native view over the same immutable source/law arrays.
    public var surface: OriginalFiniteBSplineCharts<S.Surface> {
        .init(source:surfaceSource,field:field,support:surfaceSupport,laws:surfaceLaws)
    }
}

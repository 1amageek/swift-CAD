public struct SketchCurveChain: Sendable, Hashable {
    public var segments: [SketchCurveChainSegment]
    public var vertices: [SketchCurveChainVertex]

    public init(
        segments: [SketchCurveChainSegment],
        vertices: [SketchCurveChainVertex]
    ) {
        self.segments = segments
        self.vertices = vertices
    }
}

/// One exact ordered cut on a selected original native curve owner.
public struct OriginalPlanarCurveContactCut: Sendable {
    public let endpoint: OriginalCurveRootEndpoint
    public let nativeSpanIndex: Int
    public let eventIndices: [Int]

    package init(endpoint: OriginalCurveRootEndpoint, nativeSpanIndex: Int, eventIndices: [Int]) {
        self.endpoint = endpoint; self.nativeSpanIndex = nativeSpanIndex
        self.eventIndices = eventIndices
    }
}

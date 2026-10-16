/// Ordered exact source cut with provenance in the caller's endpoint list.
public struct OriginalPlanarCurveMergedCut: Sendable {
  public let endpoint: OriginalCurveRootEndpoint
  public let nativeSpanIndex: Int
  public let inputEndpointIndices: [Int]

  package init(_ cut: OriginalPlanarCurveContactCut) {
    endpoint = cut.endpoint
    nativeSpanIndex = cut.nativeSpanIndex
    inputEndpointIndices = cut.eventIndices
  }
}

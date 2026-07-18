import CADIR

/// A sewing request paired with the source topology keys it preserves.
public struct BRepSewingExtraction: Sendable {
    public let request: BRepSewingRequest
    public let sourceStableKeys: [TopologyReference: BRepSewingStableKey]

    public init(
        request: BRepSewingRequest,
        sourceStableKeys: [TopologyReference: BRepSewingStableKey]
    ) {
        self.request = request
        self.sourceStableKeys = sourceStableKeys
    }
}

public struct SketchCurveChainVertex: Sendable, Hashable {
    public var reference: SketchReference
    public var connectedEndpointReferences: [SketchReference]

    public init(
        reference: SketchReference,
        connectedEndpointReferences: [SketchReference]
    ) {
        self.reference = reference
        self.connectedEndpointReferences = connectedEndpointReferences
    }
}

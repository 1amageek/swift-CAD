/// An ordered open or closed chain independent of face boundary roles.
public struct ShapeWire: Hashable, Sendable {
    public let edges: [ShapeEdgeUse]

    public init(edges: [ShapeEdgeUse]) {
        self.edges = edges
    }
}

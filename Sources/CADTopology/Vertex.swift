import CADCore

/// A topological vertex located at an exact model-space point.
public struct Vertex: Codable, Equatable, Sendable {
    public var id: VertexID
    public var point: Point3D

    public init(id: VertexID = VertexID(), point: Point3D) {
        self.id = id
        self.point = point
    }
}

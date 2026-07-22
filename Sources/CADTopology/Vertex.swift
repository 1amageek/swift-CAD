import CADCore

/// A topological vertex located at an exact model-space point.
public struct Vertex: Codable, Equatable, Sendable {
    public var id: VertexID
    public var point: Point3D

    public init(id: VertexID = VertexID(), point: Point3D) {
        self.id = id
        self.point = point
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case point
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.id, .point], in: decoder)
        id = try container.decode(VertexID.self, forKey: .id)
        point = try container.decode(Point3D.self, forKey: .point)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(point, forKey: .point)
    }
}

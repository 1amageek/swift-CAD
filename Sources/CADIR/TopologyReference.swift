import CADCore

public enum TopologyReference: Hashable, Codable, Sendable {
    case body(BodyID)
    case face(FaceID)
    case edge(EdgeID)
    case vertex(VertexID)

    private enum CodingKeys: String, CodingKey {
        case kind
        case bodyID
        case faceID
        case edgeID
        case vertexID
    }

    private enum Kind: String, Codable {
        case body
        case face
        case edge
        case vertex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .body:
            try container.validateOnlyExpectedKeys([.kind, .bodyID], in: decoder)
            self = .body(try container.decode(BodyID.self, forKey: .bodyID))
        case .face:
            try container.validateOnlyExpectedKeys([.kind, .faceID], in: decoder)
            self = .face(try container.decode(FaceID.self, forKey: .faceID))
        case .edge:
            try container.validateOnlyExpectedKeys([.kind, .edgeID], in: decoder)
            self = .edge(try container.decode(EdgeID.self, forKey: .edgeID))
        case .vertex:
            try container.validateOnlyExpectedKeys([.kind, .vertexID], in: decoder)
            self = .vertex(try container.decode(VertexID.self, forKey: .vertexID))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .body(bodyID):
            try container.encode(Kind.body, forKey: .kind)
            try container.encode(bodyID, forKey: .bodyID)
        case let .face(faceID):
            try container.encode(Kind.face, forKey: .kind)
            try container.encode(faceID, forKey: .faceID)
        case let .edge(edgeID):
            try container.encode(Kind.edge, forKey: .kind)
            try container.encode(edgeID, forKey: .edgeID)
        case let .vertex(vertexID):
            try container.encode(Kind.vertex, forKey: .kind)
            try container.encode(vertexID, forKey: .vertexID)
        }
    }
}

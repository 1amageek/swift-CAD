import CADCore

public enum SubshapeGeometrySignature: Hashable, Sendable {
    case body(BodyGeometrySignature)
    case vertex(point: Point3D)
    case edge(CurveSpanGeometrySignature)
    case face(FaceGeometrySignature)

    public func validate() throws {
        switch self {
        case let .body(geometry):
            try geometry.validate()
        case let .vertex(point):
            try point.validate()
        case let .edge(geometry):
            try geometry.validate()
        case let .face(geometry):
            try geometry.validate()
        }
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case kind
        case body
        case point
        case edge
        case face
    }
#endif

#if !hasFeature(Embedded)
    private enum Kind: String, Codable {
        case body
        case vertex
        case edge
        case face
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .body:
            try container.validateOnlyExpectedKeys([.kind, .body], in: decoder)
            self = .body(try container.decode(BodyGeometrySignature.self, forKey: .body))
        case .vertex:
            try container.validateOnlyExpectedKeys([.kind, .point], in: decoder)
            self = .vertex(point: try container.decode(Point3D.self, forKey: .point))
        case .edge:
            try container.validateOnlyExpectedKeys([.kind, .edge], in: decoder)
            self = .edge(try container.decode(CurveSpanGeometrySignature.self, forKey: .edge))
        case .face:
            try container.validateOnlyExpectedKeys([.kind, .face], in: decoder)
            self = .face(try container.decode(FaceGeometrySignature.self, forKey: .face))
        }
        try validate()
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .body(geometry):
            try container.encode(Kind.body, forKey: .kind)
            try container.encode(geometry, forKey: .body)
        case let .vertex(point):
            try container.encode(Kind.vertex, forKey: .kind)
            try container.encode(point, forKey: .point)
        case let .edge(geometry):
            try container.encode(Kind.edge, forKey: .kind)
            try container.encode(geometry, forKey: .edge)
        case let .face(geometry):
            try container.encode(Kind.face, forKey: .kind)
            try container.encode(geometry, forKey: .face)
        }
    }
#endif
}

#if !hasFeature(Embedded)
extension SubshapeGeometrySignature: Codable {}
#endif

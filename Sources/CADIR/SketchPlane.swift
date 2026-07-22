import CADCore

public enum SketchPlane: Codable, Sendable, Hashable {
    case xy
    case yz
    case zx
    case plane(Plane3D)

    private enum CodingKeys: String, CodingKey {
        case kind
        case plane
    }

    private enum Kind: String, Codable {
        case xy
        case yz
        case zx
        case plane
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .xy:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .xy
        case .yz:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .yz
        case .zx:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .zx
        case .plane:
            try container.validateOnlyExpectedKeys([.kind, .plane], in: decoder)
            self = .plane(try container.decode(Plane3D.self, forKey: .plane))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .xy:
            try container.encode(Kind.xy, forKey: .kind)
        case .yz:
            try container.encode(Kind.yz, forKey: .kind)
        case .zx:
            try container.encode(Kind.zx, forKey: .kind)
        case let .plane(plane):
            try container.encode(Kind.plane, forKey: .kind)
            try container.encode(plane, forKey: .plane)
        }
    }
}

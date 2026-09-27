import CADCore

/// The motion a Topology Transform applies, in the target body's own frame.
public enum TopologyMotion: Codable, Hashable, Sendable {
    case translation(DirectMoveVector)
    case rotation(DirectRotation)
    case scale(DirectScale)

    public func validate(tolerance: ModelingTolerance) throws {
        switch self {
        case let .translation(vector): try vector.validate(tolerance: tolerance)
        case let .rotation(rotation): try rotation.validate(tolerance: tolerance)
        case let .scale(scale): try scale.validate(tolerance: tolerance)
        }
    }

    /// The expressions the motion reads.
    public var expressions: [CADExpression] {
        switch self {
        case let .translation(vector): [vector.distance]
        case let .rotation(rotation): [rotation.angle]
        case let .scale(scale): scale.factors
        }
    }

    private enum Kind: String, Codable {
        case translation
        case rotation
        case scale
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case translation
        case rotation
        case scale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .translation:
            try container.validateOnlyExpectedKeys([.kind, .translation], in: decoder)
            self = .translation(try container.decode(DirectMoveVector.self, forKey: .translation))
        case .rotation:
            try container.validateOnlyExpectedKeys([.kind, .rotation], in: decoder)
            self = .rotation(try container.decode(DirectRotation.self, forKey: .rotation))
        case .scale:
            try container.validateOnlyExpectedKeys([.kind, .scale], in: decoder)
            self = .scale(try container.decode(DirectScale.self, forKey: .scale))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .translation(vector):
            try container.encode(Kind.translation, forKey: .kind)
            try container.encode(vector, forKey: .translation)
        case let .rotation(rotation):
            try container.encode(Kind.rotation, forKey: .kind)
            try container.encode(rotation, forKey: .rotation)
        case let .scale(scale):
            try container.encode(Kind.scale, forKey: .kind)
            try container.encode(scale, forKey: .scale)
        }
    }
}

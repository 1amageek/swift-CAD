import CADCore

public struct ExtrudeFeature: Codable, Sendable, Hashable {
    public var profile: ProfileReference
    public var distance: CADExpression
    public var direction: ExtrudeDirection
    public var operation: SolidOperation

    public init(
        profile: ProfileReference,
        distance: CADExpression,
        direction: ExtrudeDirection = .normal,
        operation: SolidOperation = .newBody
    ) {
        self.profile = profile
        self.distance = distance
        self.direction = direction
        self.operation = operation
    }
}

public enum SolidOperation: String, Codable, Sendable, Hashable {
    case newBody
}

public enum ExtrudeDirection: Codable, Sendable, Hashable {
    case normal
    case vector(Vector3D)
    case symmetric

    private enum CodingKeys: String, CodingKey {
        case kind
        case vector
    }

    private enum Kind: String, Codable {
        case normal
        case vector
        case symmetric
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .normal:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .normal
        case .vector:
            try container.validateOnlyExpectedKeys([.kind, .vector], in: decoder)
            self = .vector(try container.decode(Vector3D.self, forKey: .vector))
        case .symmetric:
            try container.validateOnlyExpectedKeys([.kind], in: decoder)
            self = .symmetric
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .normal:
            try container.encode(Kind.normal, forKey: .kind)
        case let .vector(vector):
            try container.encode(Kind.vector, forKey: .kind)
            try container.encode(vector, forKey: .vector)
        case .symmetric:
            try container.encode(Kind.symmetric, forKey: .kind)
        }
    }
}

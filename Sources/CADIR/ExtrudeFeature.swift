import CADCore

public struct ExtrudeFeature: Codable, Sendable, Hashable {
    public var profile: ProfileReference
    public var distance: CADExpression
    public var direction: ExtrudeDirection
    public var operation: SolidOperation
    public var resultKind: ExtrudeResultKind

    public init(
        profile: ProfileReference,
        distance: CADExpression,
        direction: ExtrudeDirection = .normal,
        operation: SolidOperation = .newBody,
        resultKind: ExtrudeResultKind = .solid
    ) {
        self.profile = profile
        self.distance = distance
        self.direction = direction
        self.operation = operation
        self.resultKind = resultKind
    }

    private enum CodingKeys: String, CodingKey {
        case profile
        case distance
        case direction
        case operation
        case resultKind
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.profile, .distance, .direction, .operation, .resultKind],
            in: decoder
        )
        profile = try container.decode(ProfileReference.self, forKey: .profile)
        distance = try container.decode(CADExpression.self, forKey: .distance)
        direction = try container.decode(ExtrudeDirection.self, forKey: .direction)
        operation = try container.decode(SolidOperation.self, forKey: .operation)
        resultKind = try container.decodeIfPresent(ExtrudeResultKind.self, forKey: .resultKind) ?? .solid
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profile, forKey: .profile)
        try container.encode(distance, forKey: .distance)
        try container.encode(direction, forKey: .direction)
        try container.encode(operation, forKey: .operation)
        if resultKind != .solid { try container.encode(resultKind, forKey: .resultKind) }
    }
}

/// Which body a linear extrusion of a closed profile builds.
///
/// A solid extrusion caps both ends of the swept wall; a sheet extrusion leaves them open and
/// sews the wall alone. The profile is the same value in both cases, so the choice belongs to the
/// feature rather than to the profile it consumes.
public enum ExtrudeResultKind: String, Codable, Sendable, Hashable {
    case solid
    case sheet
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

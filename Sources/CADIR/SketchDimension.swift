import CADCore

public enum SketchDimension: Codable, Sendable, Hashable {
    case distance(from: SketchReference, to: SketchReference, value: CADExpression)
    case angle(from: SketchReference, to: SketchReference, value: CADExpression)
    case radius(entity: SketchEntityID, value: CADExpression)
    case diameter(entity: SketchEntityID, value: CADExpression)

    private enum CodingKeys: String, CodingKey {
        case kind
        case from
        case to
        case entityID
        case value
    }

    private enum Kind: String, Codable {
        case distance
        case angle
        case radius
        case diameter
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .distance:
            try container.validateOnlyExpectedKeys([.kind, .from, .to, .value], in: decoder)
            self = .distance(
                from: try container.decode(SketchReference.self, forKey: .from),
                to: try container.decode(SketchReference.self, forKey: .to),
                value: try container.decode(CADExpression.self, forKey: .value)
            )
        case .angle:
            try container.validateOnlyExpectedKeys([.kind, .from, .to, .value], in: decoder)
            self = .angle(
                from: try container.decode(SketchReference.self, forKey: .from),
                to: try container.decode(SketchReference.self, forKey: .to),
                value: try container.decode(CADExpression.self, forKey: .value)
            )
        case .radius:
            try container.validateOnlyExpectedKeys([.kind, .entityID, .value], in: decoder)
            self = .radius(
                entity: try container.decode(SketchEntityID.self, forKey: .entityID),
                value: try container.decode(CADExpression.self, forKey: .value)
            )
        case .diameter:
            try container.validateOnlyExpectedKeys([.kind, .entityID, .value], in: decoder)
            self = .diameter(
                entity: try container.decode(SketchEntityID.self, forKey: .entityID),
                value: try container.decode(CADExpression.self, forKey: .value)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .distance(from, to, value):
            try container.encode(Kind.distance, forKey: .kind)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(value, forKey: .value)
        case let .angle(from, to, value):
            try container.encode(Kind.angle, forKey: .kind)
            try container.encode(from, forKey: .from)
            try container.encode(to, forKey: .to)
            try container.encode(value, forKey: .value)
        case let .radius(entityID, value):
            try container.encode(Kind.radius, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
            try container.encode(value, forKey: .value)
        case let .diameter(entityID, value):
            try container.encode(Kind.diameter, forKey: .kind)
            try container.encode(entityID, forKey: .entityID)
            try container.encode(value, forKey: .value)
        }
    }
}

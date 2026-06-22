import CADCore

public enum SketchReference: Codable, Hashable, Sendable {
    case entity(SketchEntityID)
    case lineStart(SketchEntityID)
    case lineEnd(SketchEntityID)
    case circleCenter(SketchEntityID)
    case circleRadius(SketchEntityID)
    case arcCenter(SketchEntityID)
    case arcStart(SketchEntityID)
    case arcEnd(SketchEntityID)
    case arcRadius(SketchEntityID)
    case splineControlPoint(entity: SketchEntityID, index: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case entityID
        case controlPointIndex
    }

    private enum Kind: String, Codable {
        case entity
        case lineStart
        case lineEnd
        case circleCenter
        case circleRadius
        case arcCenter
        case arcStart
        case arcEnd
        case arcRadius
        case splineControlPoint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let expectedKeys: Set<CodingKeys> = kind == .splineControlPoint
            ? [.kind, .entityID, .controlPointIndex]
            : [.kind, .entityID]
        try container.validateOnlyExpectedKeys(expectedKeys, in: decoder)
        let entityID = try container.decode(SketchEntityID.self, forKey: .entityID)
        switch kind {
        case .entity:
            self = .entity(entityID)
        case .lineStart:
            self = .lineStart(entityID)
        case .lineEnd:
            self = .lineEnd(entityID)
        case .circleCenter:
            self = .circleCenter(entityID)
        case .circleRadius:
            self = .circleRadius(entityID)
        case .arcCenter:
            self = .arcCenter(entityID)
        case .arcStart:
            self = .arcStart(entityID)
        case .arcEnd:
            self = .arcEnd(entityID)
        case .arcRadius:
            self = .arcRadius(entityID)
        case .splineControlPoint:
            self = .splineControlPoint(
                entity: entityID,
                index: try container.decode(Int.self, forKey: .controlPointIndex)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let entityID: SketchEntityID
        let kind: Kind
        switch self {
        case let .entity(id):
            entityID = id
            kind = .entity
        case let .lineStart(id):
            entityID = id
            kind = .lineStart
        case let .lineEnd(id):
            entityID = id
            kind = .lineEnd
        case let .circleCenter(id):
            entityID = id
            kind = .circleCenter
        case let .circleRadius(id):
            entityID = id
            kind = .circleRadius
        case let .arcCenter(id):
            entityID = id
            kind = .arcCenter
        case let .arcStart(id):
            entityID = id
            kind = .arcStart
        case let .arcEnd(id):
            entityID = id
            kind = .arcEnd
        case let .arcRadius(id):
            entityID = id
            kind = .arcRadius
        case let .splineControlPoint(id, index):
            entityID = id
            kind = .splineControlPoint
            try container.encode(index, forKey: .controlPointIndex)
        }
        try container.encode(kind, forKey: .kind)
        try container.encode(entityID, forKey: .entityID)
    }
}

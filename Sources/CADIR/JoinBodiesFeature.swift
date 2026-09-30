import CADCore

/// What joining makes of its targets.
public enum JoinBodiesMode: String, Codable, Hashable, Sendable {
    /// Solids whose material does not meet become the components of one solid body.
    case solidComponents
    /// Sheets sewn along their exactly matching edges into one sheet that stays open.
    case sewnSheet
    /// Sheets sewn along their exactly matching edges into one closed shell bounding a solid.
    case sewnSolid

    /// The port the joined body leaves through.
    public var outputPort: FeaturePort {
        self == .sewnSheet ? .sheet : .body
    }

    /// The port every target must leave through.
    public var targetPort: FeaturePort {
        self == .solidComponents ? .body : .sheet
    }
}

public struct JoinBodiesFeature: Codable, Hashable, Sendable {
    public let targets: [PatternTargetReference]
    public let mode: JoinBodiesMode

    public init(targets: [PatternTargetReference], mode: JoinBodiesMode = .solidComponents) {
        self.targets = targets
        self.mode = mode
    }

    public func validate() throws {
        guard targets.count >= 2 else {
            throw FeatureEvaluationError.invalidGraph("Join bodies features require at least two target bodies.")
        }
        let targetFeatureIDs = targets.map(\.featureID)
        guard Set(targetFeatureIDs).count == targetFeatureIDs.count else {
            throw FeatureEvaluationError.invalidGraph("Join bodies target references must be unique.")
        }
        try targets.forEach { try $0.validate() }
    }

    private enum CodingKeys: String, CodingKey {
        case targets
        case mode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.targets, .mode], in: decoder)
        targets = try container.decode([PatternTargetReference].self, forKey: .targets)
        mode = try container.decode(JoinBodiesMode.self, forKey: .mode)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targets, forKey: .targets)
        try container.encode(mode, forKey: .mode)
    }
}

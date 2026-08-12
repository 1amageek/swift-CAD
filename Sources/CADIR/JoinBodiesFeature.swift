import CADCore

public struct JoinBodiesFeature: Codable, Hashable, Sendable {
    public let targets: [PatternTargetReference]

    public init(targets: [PatternTargetReference]) {
        self.targets = targets
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
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.targets], in: decoder)
        targets = try container.decode([PatternTargetReference].self, forKey: .targets)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targets, forKey: .targets)
    }
}

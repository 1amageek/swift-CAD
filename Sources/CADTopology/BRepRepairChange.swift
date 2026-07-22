public struct BRepRepairChange: Codable, Equatable, Sendable {
    public let action: BRepRepairAction
    public let scope: TopologyValidationScope
    public let affectedEntityIDs: [String]
    public let message: String

    public init(
        action: BRepRepairAction,
        scope: TopologyValidationScope,
        affectedEntityIDs: [String],
        message: String
    ) {
        self.action = action
        self.scope = scope
        self.affectedEntityIDs = affectedEntityIDs
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case action
        case scope
        case affectedEntityIDs
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.action, .scope, .affectedEntityIDs, .message],
            in: decoder
        )
        self.init(
            action: try container.decode(BRepRepairAction.self, forKey: .action),
            scope: try container.decode(TopologyValidationScope.self, forKey: .scope),
            affectedEntityIDs: try container.decode([String].self, forKey: .affectedEntityIDs),
            message: try container.decode(String.self, forKey: .message)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(scope, forKey: .scope)
        try container.encode(affectedEntityIDs, forKey: .affectedEntityIDs)
        try container.encode(message, forKey: .message)
    }
}

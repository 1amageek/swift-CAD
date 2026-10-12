public struct BRepRepairChange: Equatable, Sendable {
    public let action: BRepRepairAction
    public let scope: TopologyValidationScope
    public let affectedEntityIDs: [String]
    public let maximumDisplacement: Double
    public let toleranceIncrease: Double
    public let generatedEntityIDs: [String]
    public let deletedEntityIDs: [String]
    public let message: String

    public init(
        action: BRepRepairAction,
        scope: TopologyValidationScope,
        affectedEntityIDs: [String],
        message: String,
        maximumDisplacement: Double = 0, toleranceIncrease: Double = 0,
        generatedEntityIDs: [String] = [], deletedEntityIDs: [String] = []
    ) {
        self.action = action
        self.scope = scope
        self.affectedEntityIDs = affectedEntityIDs
        self.message = message
        self.maximumDisplacement = maximumDisplacement
        self.toleranceIncrease = toleranceIncrease
        self.generatedEntityIDs = generatedEntityIDs
        self.deletedEntityIDs = deletedEntityIDs
    }

    #if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case action
        case scope
        case affectedEntityIDs
        case maximumDisplacement, toleranceIncrease, generatedEntityIDs, deletedEntityIDs
        case message
    }
    #endif

    #if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.action, .scope, .affectedEntityIDs, .message, .maximumDisplacement, .toleranceIncrease, .generatedEntityIDs, .deletedEntityIDs],
            in: decoder
        )
        self.init(
            action: try container.decode(BRepRepairAction.self, forKey: .action),
            scope: try container.decode(TopologyValidationScope.self, forKey: .scope),
            affectedEntityIDs: try container.decode([String].self, forKey: .affectedEntityIDs),
            message: try container.decode(String.self, forKey: .message),
            maximumDisplacement: try container.decodeIfPresent(Double.self, forKey: .maximumDisplacement) ?? 0,
            toleranceIncrease: try container.decodeIfPresent(Double.self, forKey: .toleranceIncrease) ?? 0,
            generatedEntityIDs: try container.decodeIfPresent([String].self, forKey: .generatedEntityIDs) ?? [],
            deletedEntityIDs: try container.decodeIfPresent([String].self, forKey: .deletedEntityIDs) ?? []
        )
    }
    #endif

    #if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(scope, forKey: .scope)
        try container.encode(affectedEntityIDs, forKey: .affectedEntityIDs)
        try container.encode(message, forKey: .message)
        try container.encode(maximumDisplacement, forKey: .maximumDisplacement)
        try container.encode(toleranceIncrease, forKey: .toleranceIncrease)
        try container.encode(generatedEntityIDs, forKey: .generatedEntityIDs)
        try container.encode(deletedEntityIDs, forKey: .deletedEntityIDs)
    }
    #endif
}

#if !hasFeature(Embedded)
extension BRepRepairChange: Codable {}
#endif

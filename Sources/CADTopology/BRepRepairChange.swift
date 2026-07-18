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
}

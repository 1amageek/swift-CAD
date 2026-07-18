import CADCore

public struct BRepRepairDiagnostic: Codable, Equatable, Sendable {
    public let action: BRepRepairAction
    public let code: KernelErrorCode
    public let entityID: String?
    public let message: String

    public init(
        action: BRepRepairAction,
        code: KernelErrorCode,
        entityID: String? = nil,
        message: String
    ) {
        self.action = action
        self.code = code
        self.entityID = entityID
        self.message = message
    }
}

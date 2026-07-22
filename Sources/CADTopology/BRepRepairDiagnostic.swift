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

    private enum CodingKeys: String, CodingKey {
        case action
        case code
        case entityID
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.action, .code, .entityID, .message],
            in: decoder
        )
        self.init(
            action: try container.decode(BRepRepairAction.self, forKey: .action),
            code: try container.decode(KernelErrorCode.self, forKey: .code),
            entityID: try container.decodeIfPresent(String.self, forKey: .entityID),
            message: try container.decode(String.self, forKey: .message)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(entityID, forKey: .entityID)
        try container.encode(message, forKey: .message)
    }
}

import CADCore

public struct TopologyValidationDiagnostic: Codable, Equatable, Sendable {
    public let scope: TopologyValidationScope
    public let code: KernelErrorCode
    public let entityID: String?
    public let residual: Double?
    public let message: String

    public init(
        scope: TopologyValidationScope,
        code: KernelErrorCode,
        entityID: String? = nil,
        residual: Double? = nil,
        message: String
    ) {
        self.scope = scope
        self.code = code
        self.entityID = entityID
        self.residual = residual
        self.message = message
    }

    private enum CodingKeys: String, CodingKey {
        case scope
        case code
        case entityID
        case residual
        case message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.scope, .code, .entityID, .residual, .message],
            in: decoder
        )
        self.init(
            scope: try container.decode(TopologyValidationScope.self, forKey: .scope),
            code: try container.decode(KernelErrorCode.self, forKey: .code),
            entityID: try container.decodeIfPresent(String.self, forKey: .entityID),
            residual: try container.decodeIfPresent(Double.self, forKey: .residual),
            message: try container.decode(String.self, forKey: .message)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scope, forKey: .scope)
        try container.encode(code, forKey: .code)
        try container.encodeIfPresent(entityID, forKey: .entityID)
        try container.encodeIfPresent(residual, forKey: .residual)
        try container.encode(message, forKey: .message)
    }
}

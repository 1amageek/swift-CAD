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
}

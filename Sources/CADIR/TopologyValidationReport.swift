import CADCore

public enum TopologyValidationScope: String, Codable, Hashable, Sendable, CaseIterable {
    case references
    case loops
    case pcurves
    case orientation
    case manifold
    case watertight
    case volume
}

public struct TopologyValidationDiagnostic: Codable, Equatable, Sendable {
    public let scope: TopologyValidationScope
    public let code: KernelErrorCode
    public let message: String

    public init(scope: TopologyValidationScope, code: KernelErrorCode, message: String) {
        self.scope = scope
        self.code = code
        self.message = message
    }
}

public struct TopologyValidationReport: Codable, Equatable, Sendable {
    public let isValid: Bool
    public let diagnostics: [TopologyValidationDiagnostic]

    public init(isValid: Bool, diagnostics: [TopologyValidationDiagnostic] = []) {
        self.isValid = isValid
        self.diagnostics = diagnostics
    }
}

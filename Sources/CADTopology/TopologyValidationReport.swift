import CADCore

public struct TopologyValidationReport: Codable, Equatable, Sendable {
    public let isValid: Bool
    public let diagnostics: [TopologyValidationDiagnostic]

    public init(isValid: Bool, diagnostics: [TopologyValidationDiagnostic] = []) {
        self.isValid = isValid
        self.diagnostics = diagnostics
    }
}

import CADCore

public struct TopologyValidationReport: Codable, Equatable, Sendable {
    public let isValid: Bool
    public let diagnostics: [TopologyValidationDiagnostic]

    public init(isValid: Bool, diagnostics: [TopologyValidationDiagnostic] = []) {
        self.isValid = isValid
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case isValid
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.isValid, .diagnostics], in: decoder)
        self.init(
            isValid: try container.decode(Bool.self, forKey: .isValid),
            diagnostics: try container.decode(
                [TopologyValidationDiagnostic].self,
                forKey: .diagnostics
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isValid, forKey: .isValid)
        try container.encode(diagnostics, forKey: .diagnostics)
    }
}

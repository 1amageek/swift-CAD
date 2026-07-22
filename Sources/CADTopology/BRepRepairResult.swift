public struct BRepRepairResult: Codable, Equatable, Sendable {
    public let model: BRepModel
    public let before: TopologyValidationReport
    public let after: TopologyValidationReport
    public let changes: [BRepRepairChange]
    public let diagnostics: [BRepRepairDiagnostic]

    public init(
        model: BRepModel,
        before: TopologyValidationReport,
        after: TopologyValidationReport,
        changes: [BRepRepairChange],
        diagnostics: [BRepRepairDiagnostic]
    ) {
        self.model = model
        self.before = before
        self.after = after
        self.changes = changes
        self.diagnostics = diagnostics
    }

    private enum CodingKeys: String, CodingKey {
        case model
        case before
        case after
        case changes
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.model, .before, .after, .changes, .diagnostics],
            in: decoder
        )
        self.init(
            model: try container.decode(BRepModel.self, forKey: .model),
            before: try container.decode(TopologyValidationReport.self, forKey: .before),
            after: try container.decode(TopologyValidationReport.self, forKey: .after),
            changes: try container.decode([BRepRepairChange].self, forKey: .changes),
            diagnostics: try container.decode(
                [BRepRepairDiagnostic].self,
                forKey: .diagnostics
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(before, forKey: .before)
        try container.encode(after, forKey: .after)
        try container.encode(changes, forKey: .changes)
        try container.encode(diagnostics, forKey: .diagnostics)
    }
}

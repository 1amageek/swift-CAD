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
}

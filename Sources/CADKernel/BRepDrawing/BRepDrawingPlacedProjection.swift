import CADGeometry
/// Immutable geometric occurrence receipt consumed by native format exchange.
public struct BRepDrawingPlacedProjection: Sendable {
    public let original: BRepDrawingProjection
    public let placements: [BRepDrawingPlacement]
    public let uses: [BRepDrawingPlacedUse]

    /// Proves original CAD source freshness; the scene owner admits current placement separately.
    public func validateCurrent(_ evaluated: EvaluatedDocument) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validateCurrent(evaluated, using: &execution)
    }

    public func validateCurrent(_ evaluated: EvaluatedDocument, using execution: inout OriginalQueryExecution) throws {
        try execution.checkpoint()
        try original.validateCurrent(evaluated, using: &execution)
    }
}

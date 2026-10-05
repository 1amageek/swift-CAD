/// Immutable geometric occurrence receipt consumed by native format exchange.
public struct BRepDrawingPlacedProjection: Sendable {
    public let original: BRepDrawingProjection
    public let placements: [BRepDrawingPlacement]
    public let uses: [BRepDrawingPlacedUse]

    /// Proves original CAD source freshness; the scene owner admits current placement separately.
    public func validateCurrent(_ evaluated: EvaluatedDocument) throws {
        try original.validateCurrent(evaluated)
    }
}

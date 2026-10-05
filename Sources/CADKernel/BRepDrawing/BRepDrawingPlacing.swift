public protocol BRepDrawingPlacing: Sendable {
    func place(_ original: BRepDrawingProjection, in evaluated: EvaluatedDocument,
               placements: [BRepDrawingPlacement], maximumPlacements: Int,
               maximumProjectedUses: Int) throws -> BRepDrawingPlacedProjection
}

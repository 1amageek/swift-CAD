import CADGeometry

/// Actual directed topology use through the retained original occurrence law.
public struct BRepDrawingPlacedUse: Sendable {
    public let placement: BRepDrawingPlacement
    public let original: BRepDrawingProjectedUse
    public let curve: OrthographicProjectedCurve
}

import CADGeometry

public protocol BRepDrawingProjectedContactPreparing: Sendable {
    func prepare(_ projection: BRepDrawingPlacedProjection, silhouettes: [BRepDrawingSilhouettes],
        in evaluated: EvaluatedDocument, maximumPartitions: Int,
        usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingProjectedContacts
}

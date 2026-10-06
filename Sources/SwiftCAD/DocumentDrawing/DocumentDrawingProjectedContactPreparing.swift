import CADGeometry
import CADIR
import CADKernel

public protocol DocumentDrawingProjectedContactPreparing: Sendable {
    func prepare(_ projection: BRepDrawingPlacedProjection, silhouettes: [BRepDrawingSilhouettes],
        document: CADDocument, currentEvaluation: EvaluatedDocument, maximumPartitions: Int,
        usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingProjectedContacts
}

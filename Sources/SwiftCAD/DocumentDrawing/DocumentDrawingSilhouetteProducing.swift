import CADGeometry
import CADIR
import CADKernel

public protocol DocumentDrawingSilhouetteProducing: Sendable {
    func silhouettes(_ placement: BRepDrawingPlacement, document: CADDocument,
        currentEvaluation: EvaluatedDocument, onto frame: OrthographicProjectionFrame,
        maximumSourceEntities: Int, maximumSourceFaces: Int, maximumProjectedSpans: Int,
        maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
        usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingSilhouettes
    func silhouettes(document: CADDocument, currentEvaluation: EvaluatedDocument,
        onto frame: OrthographicProjectionFrame, maximumSourceFaces: Int,
        maximumProjectedSpans: Int, maximumControlPointCount: Int,
        maximumBoundaryCurveCount: Int, usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingSilhouettes
}

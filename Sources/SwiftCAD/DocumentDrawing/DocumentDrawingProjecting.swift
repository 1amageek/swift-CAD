import CADGeometry
import CADIR
import CADKernel

public protocol DocumentDrawingProjecting: Sendable {
    func projectEdges(document: CADDocument, currentEvaluation: EvaluatedDocument,
                      onto frame: OrthographicProjectionFrame,
                      maximumProjectedUses: Int) throws -> BRepDrawingProjection
}

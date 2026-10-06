import CADCore
import CADGeometry
import CADIR
import CADKernel

public protocol DocumentDrawingSectioning: Sendable {
    func section(document: CADDocument, currentEvaluation: EvaluatedDocument,
                 placement: BRepDrawingPlacement,
                 on support: BRepDrawingCuttingSupport, projectionFrame: OrthographicProjectionFrame,
                 maximumSourceFaces: Int, maximumComponents: Int, maximumSourceEntities: Int,
                 maximumPreparationWork: Int, maximumPreparationBytes: Int,
                 maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int) throws -> BRepDrawingSection

    func section(document: CADDocument, currentEvaluation: EvaluatedDocument,
                 bodyIDs: [BodyID], on support: BRepDrawingCuttingSupport, projectionFrame: OrthographicProjectionFrame,
                 maximumSourceFaces: Int, maximumComponents: Int, maximumPreparationWork: Int,
                 maximumPreparationBytes: Int, maximumSourceDepth: Int, maximumSubdivisionDepth: Int,
                 maximumAlgebraicDepth: Int) throws -> BRepDrawingSection
    func section(document: CADDocument, currentEvaluation: EvaluatedDocument,
                 on frame: OrthographicProjectionFrame,
                 maximumSourceFaces: Int, maximumComponents: Int) throws -> BRepDrawingSection
    func section(document: CADDocument, currentEvaluation: EvaluatedDocument,
                 bodyIDs: [BodyID], on frame: OrthographicProjectionFrame,
                 maximumSourceFaces: Int, maximumComponents: Int) throws -> BRepDrawingSection
    func section(document: CADDocument, currentEvaluation: EvaluatedDocument,
                 placement: BRepDrawingPlacement, on frame: OrthographicProjectionFrame,
                 maximumSourceFaces: Int, maximumComponents: Int,
                 maximumSourceEntities: Int, maximumPreparationWork: Int) throws -> BRepDrawingSection
}

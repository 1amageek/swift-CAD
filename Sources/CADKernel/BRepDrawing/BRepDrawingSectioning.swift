import CADCore
import CADGeometry

public protocol BRepDrawingSectioning: Sendable {
    func section(placement: BRepDrawingPlacement, in evaluated: EvaluatedDocument,
                 on support: BRepDrawingCuttingSupport, projectionFrame: OrthographicProjectionFrame,
                 maximumSourceFaces: Int, maximumComponents: Int, maximumSourceEntities: Int,
                 maximumPreparationWork: Int, maximumPreparationBytes: Int,
                 maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int) throws -> BRepDrawingSection

    func section(bodyIDs: [BodyID], in evaluated: EvaluatedDocument,
                 on support: BRepDrawingCuttingSupport, projectionFrame: OrthographicProjectionFrame,
                 maximumSourceFaces: Int, maximumComponents: Int,
                 maximumPreparationWork: Int, maximumPreparationBytes: Int,
                 maximumSourceDepth: Int, maximumSubdivisionDepth: Int, maximumAlgebraicDepth: Int) throws -> BRepDrawingSection
    func section(in evaluated: EvaluatedDocument, on frame: OrthographicProjectionFrame,
                 maximumSourceFaces: Int, maximumComponents: Int) throws -> BRepDrawingSection
    func section(bodyIDs: [BodyID], in evaluated: EvaluatedDocument, on frame: OrthographicProjectionFrame,
                 maximumSourceFaces: Int, maximumComponents: Int) throws -> BRepDrawingSection
    func section(placement: BRepDrawingPlacement, in evaluated: EvaluatedDocument,
                 on frame: OrthographicProjectionFrame, maximumSourceFaces: Int, maximumComponents: Int,
                 maximumSourceEntities: Int, maximumPreparationWork: Int) throws -> BRepDrawingSection
}

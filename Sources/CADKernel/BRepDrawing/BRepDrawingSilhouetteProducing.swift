import CADGeometry

public protocol BRepDrawingSilhouetteProducing: Sendable {
    func silhouettes(_ placement: BRepDrawingPlacement, in evaluated: EvaluatedDocument,
                     onto frame: OrthographicProjectionFrame, maximumSourceEntities: Int,
                     maximumSourceFaces: Int, maximumProjectedSpans: Int,
                     maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
                     usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingSilhouettes
    func silhouettes(in evaluated: EvaluatedDocument, onto frame: OrthographicProjectionFrame,
                     maximumSourceFaces: Int, maximumProjectedSpans: Int,
                     maximumControlPointCount: Int, maximumBoundaryCurveCount: Int,
                     usage: inout SurfaceSilhouetteUsage) throws -> BRepDrawingSilhouettes
}

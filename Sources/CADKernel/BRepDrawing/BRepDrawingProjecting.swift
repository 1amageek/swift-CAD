import CADGeometry

public protocol BRepDrawingProjecting: Sendable {
    func projectEdges(in evaluated: EvaluatedDocument, onto frame: OrthographicProjectionFrame,
                      maximumProjectedUses: Int) throws -> BRepDrawingProjection
}

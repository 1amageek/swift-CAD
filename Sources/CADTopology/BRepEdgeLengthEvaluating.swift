import CADCore
import CADGeometry

/// Resolves certified physical lengths for topological edges.
public protocol BRepEdgeLengthEvaluating: Sendable {
    func lengthEnclosure(
        of edge: Edge,
        in model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> CurveArcLengthEnclosure
}

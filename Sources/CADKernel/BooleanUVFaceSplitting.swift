import CADCore
import CADIR
import CADTopology

public protocol BooleanUVFaceSplitting: Sendable {
    func splitGraph(
        intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanUVSplitGraph
}

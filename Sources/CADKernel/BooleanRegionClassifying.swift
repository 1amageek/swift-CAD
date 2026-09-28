import CADCore
import CADIR
import CADTopology

public protocol BooleanRegionClassifying: Sendable {
    func classificationGraph(
        uvSplitGraph: BooleanUVSplitGraph,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ) throws -> BooleanClassificationGraph
}

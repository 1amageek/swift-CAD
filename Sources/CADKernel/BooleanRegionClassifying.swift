import CADCore
import CADGeometry
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
    func classificationGraph(
        uvSplitGraph: BooleanUVSplitGraph,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        model: BRepModel,
        operands: BooleanOperandContext,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanClassificationGraph
}

public extension BooleanRegionClassifying {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected providers must preserve the direct
    // classification execution before admitted Boolean callers can use them.
    func classificationGraph(uvSplitGraph: BooleanUVSplitGraph, targetBodyIDs: [BodyID],
        toolBodyID: BodyID, model: BRepModel, operands: BooleanOperandContext,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution)
        throws -> BooleanClassificationGraph {
        throw KernelError(phase: .classification, code: .unsupportedCapability, tolerance: tolerance,
            message: "The injected region classifier lacks direct execution.")
    }
}

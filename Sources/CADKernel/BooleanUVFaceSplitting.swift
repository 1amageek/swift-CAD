import CADCore
import CADGeometry
import CADIR
import CADTopology

public protocol BooleanUVFaceSplitting: Sendable {
    func splitGraph(
        intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel,
        tolerance: ModelingTolerance
    ) throws -> BooleanUVSplitGraph
    func splitGraph(
        intersectionGraph: BooleanIntersectionGraph,
        model: BRepModel,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanUVSplitGraph
}

public extension BooleanUVFaceSplitting {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected splitters must retain the caller's
    // execution across original clipping and final publication before admitted success.
    func splitGraph(intersectionGraph: BooleanIntersectionGraph, model: BRepModel,
        tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> BooleanUVSplitGraph {
        throw KernelError(phase: .topology, code: .unsupportedCapability, tolerance: tolerance,
            message: "The injected UV splitter lacks direct execution.")
    }
}

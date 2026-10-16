import CADCore
import CADGeometry
import CADIR

public protocol BooleanResultRegionSelecting: Sendable {
    func selectionGraph(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        rule: BooleanRegionSelectionRule,
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionGraph
    func selectionGraph(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        rule: BooleanRegionSelectionRule,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanRegionSelectionGraph
}

public extension BooleanResultRegionSelecting {
    // FIXME(INCOMPLETE_IMPLEMENTATION): Injected selection providers must visit the
    // complete graph under the caller's direct execution before admitted success.
    func selectionGraph(operation: BooleanOperation, classificationGraph: BooleanClassificationGraph,
        rule: BooleanRegionSelectionRule, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> BooleanRegionSelectionGraph {
        throw KernelError(phase: .classification, code: .unsupportedCapability, tolerance: tolerance,
            message: "The injected region selector lacks direct execution.")
    }
}

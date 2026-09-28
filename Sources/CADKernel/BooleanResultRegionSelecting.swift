import CADCore
import CADIR

public protocol BooleanResultRegionSelecting: Sendable {
    func selectionGraph(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        rule: BooleanRegionSelectionRule,
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionGraph
}

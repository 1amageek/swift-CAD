import CADCore
import CADIR

public protocol BooleanResultRegionSelecting: Sendable {
    func selectionGraph(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionGraph
}

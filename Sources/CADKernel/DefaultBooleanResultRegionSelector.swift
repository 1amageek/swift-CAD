import CADCore
import CADIR

public struct DefaultBooleanResultRegionSelector: BooleanResultRegionSelecting {
    public init() {}

    public func selectionGraph(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionGraph {
        try tolerance.validate()
        guard classificationGraph.samples.allSatisfy({ $0.classification != .boundary }) else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Boolean result-region selection requires resolved inside or outside classifications."
            )
        }
        let decisions = classificationGraph.samples.map { sample in
            return BooleanRegionSelectionGraph.Decision(
                sample: sample,
                action: BooleanRegionSelectionRule().action(
                    operation: operation,
                    sample: sample
                )
            )
        }
        let graph = BooleanRegionSelectionGraph(decisions: decisions)
        try graph.validate(
            operation: operation,
            classificationGraph: classificationGraph,
            tolerance: tolerance
        )
        return graph
    }
}

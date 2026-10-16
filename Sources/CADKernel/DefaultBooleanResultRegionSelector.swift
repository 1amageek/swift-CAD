import CADCore
import CADGeometry
import CADIR

public struct DefaultBooleanResultRegionSelector: BooleanResultRegionSelecting {
    public init() {}

    public func selectionGraph(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        rule: BooleanRegionSelectionRule,
        tolerance: ModelingTolerance
    ) throws -> BooleanRegionSelectionGraph {
        var execution = try OriginalQueryExecution.kernelOriginal()
        return try selectionGraph(operation: operation, classificationGraph: classificationGraph, rule: rule, tolerance: tolerance, using: &execution)
    }

    public func selectionGraph(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        rule: BooleanRegionSelectionRule,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws -> BooleanRegionSelectionGraph {
        try execution.checkpoint()
        try tolerance.validate()
        var decisions: [BooleanRegionSelectionGraph.Decision] = []
        try execution.retainKernelValues(count: classificationGraph.samples.count,
            stride: MemoryLayout<BooleanRegionSelectionGraph.Decision>.stride)
        decisions.reserveCapacity(classificationGraph.samples.count)
        for sample in classificationGraph.samples {
            try execution.consumeWork(1)
            guard sample.classification != .boundary else {
                throw KernelError(phase: .classification, code: .classificationFailure, tolerance: tolerance,
                    message: "Boolean result-region selection requires resolved inside or outside classifications.")
            }
            decisions.append(.init(sample: sample, action: rule.action(operation: operation, sample: sample)))
        }
        let graph = BooleanRegionSelectionGraph(decisions: decisions)
        try graph.validate(
            operation: operation,
            classificationGraph: classificationGraph,
            rule: rule,
            tolerance: tolerance, using: &execution
        )
        try execution.checkpoint()
        return graph
    }
}

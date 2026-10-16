import CADCore
import CADGeometry
import CADIR

public struct BooleanRegionSelectionGraph: Hashable, Sendable {
    public struct Decision: Hashable, Sendable {
        public let sample: BooleanClassificationGraph.Sample
        public let action: BooleanRegionSelectionAction

        public init(
            sample: BooleanClassificationGraph.Sample,
            action: BooleanRegionSelectionAction
        ) {
            self.sample = sample
            self.action = action
        }
    }

    public let decisions: [Decision]

    public init(decisions: [Decision]) {
        self.decisions = decisions
    }

    public func validate(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        rule: BooleanRegionSelectionRule,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.kernelOriginal()
        try validate(operation: operation, classificationGraph: classificationGraph, rule: rule, tolerance: tolerance, using: &execution)
    }

    public func validate(
        operation: BooleanOperation,
        classificationGraph: BooleanClassificationGraph,
        rule: BooleanRegionSelectionRule,
        tolerance: ModelingTolerance
    ,
        using execution: inout OriginalQueryExecution
    ) throws {
        try execution.checkpoint()
        try tolerance.validate()
        try execution.consumeWork(decisions.count)
        try execution.consumeWork(classificationGraph.samples.count)
        try execution.retainKernelValues(count: decisions.count,
            stride: 2 * MemoryLayout<BooleanClassificationGraph.Sample>.stride + MemoryLayout<Decision>.stride)
        try execution.retainKernelValues(count: classificationGraph.samples.count,
            stride: MemoryLayout<BooleanClassificationGraph.Sample>.stride)
        guard decisions.count == classificationGraph.samples.count,
              Set(decisions.map(\.sample)) == Set(classificationGraph.samples),
              Set(decisions).count == decisions.count,
              decisions.allSatisfy({ decision in
                  decision.action == rule.action(
                      operation: operation,
                      sample: decision.sample
                  )
              }) else {
            throw KernelError(
                phase: .classification,
                code: .classificationFailure,
                tolerance: tolerance,
                message: "Boolean region selection must decide every sample exactly once using the operation rule."
            )
        }
    }
}

#if !hasFeature(Embedded)
extension BooleanRegionSelectionGraph: Codable {}
extension BooleanRegionSelectionGraph.Decision: Codable {}
#endif

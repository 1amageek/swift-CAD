import CADCore
import CADIR

public struct BooleanRegionSelectionGraph: Codable, Hashable, Sendable {
    public struct Decision: Codable, Hashable, Sendable {
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
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard decisions.count == classificationGraph.samples.count,
              Set(decisions.map(\.sample)) == Set(classificationGraph.samples),
              Set(decisions).count == decisions.count,
              decisions.allSatisfy({ decision in
                  decision.action == BooleanRegionSelectionRule().action(
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

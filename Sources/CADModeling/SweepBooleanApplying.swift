import CADCore
import CADIR
import CADTopology

public protocol SweepBooleanApplying: Sendable {
    func apply(
        operation: SweepBooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        toolResult: EvaluationResult,
        targetSubshapes: [SubshapeID: TopologyReference],
        inputLineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult
}

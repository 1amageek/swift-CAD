import CADCore
import CADIR
import CADTopology

public protocol BooleanOperationApplying: Sendable {
    /// One Boolean pass combining the targets with the tool, each operand's material taken as
    /// `materials` says.
    func apply(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        toolSubshapes: [SubshapeID: TopologyReference],
        inputLineage: [SubshapeID: TopologyLineage],
        materials: BooleanMaterials,
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult
}

extension BooleanOperationApplying {
    /// One Boolean pass of two solids taken as their volumes.
    public func apply(
        operation: BooleanOperation,
        targetBodyIDs: [BodyID],
        toolBodyID: BodyID,
        keepTools: Bool,
        featureID: FeatureID,
        model: BRepModel,
        subshapes: [SubshapeID: TopologyReference],
        toolSubshapes: [SubshapeID: TopologyReference],
        inputLineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance
    ) throws -> EvaluationResult {
        try apply(
            operation: operation,
            targetBodyIDs: targetBodyIDs,
            toolBodyID: toolBodyID,
            keepTools: keepTools,
            featureID: featureID,
            model: model,
            subshapes: subshapes,
            toolSubshapes: toolSubshapes,
            inputLineage: inputLineage,
            materials: .default,
            tolerance: tolerance
        )
    }
}

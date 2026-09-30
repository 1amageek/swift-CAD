import CADCore
import CADGeometry
import CADIR
import CADTopology

/// Moves every placed join target rigidly into the joined body's frame, each move one internal
/// stage (`joinOperandPlacement`), so evaluating a join and asking whether sheets close see the
/// same bodies.
package struct JoinTargetPlacement {
    private let relocator: (any ExactBodyPatternRebuilding)?

    package init(relocator: (any ExactBodyPatternRebuilding)?) {
        self.relocator = relocator
    }

    /// The staged context with every placed target moved, and each target's body in it, in
    /// target order.
    package func place(
        _ targets: [JoinBodiesTargetReference],
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> (stages: FeatureEvaluationStages, bodyIDs: [BodyID]) {
        var stages = FeatureEvaluationStages(context)
        var bodyIDs: [BodyID] = []
        for (ordinal, target) in targets.enumerated() {
            let bodyID = try context.bodyID(generatedBy: target.featureID)
            guard let placement = target.placement else {
                bodyIDs.append(bodyID)
                continue
            }
            guard let relocator else {
                throw KernelError(
                    phase: .evaluation,
                    code: .unsupportedCapability,
                    featureID: featureID,
                    tolerance: context.tolerance,
                    message: "This evaluator cannot move a placed body to join it."
                )
            }
            try placement.validate(tolerance: context.tolerance)
            let stageID = featureEvaluationStageID(featureID: featureID, domain: .joinOperandPlacement, ordinal: UInt64(ordinal))
            let staged = stages.context
            let moved = try FeatureEvaluationBoundary.evaluate(featureID: featureID, tolerance: context.tolerance) {
                try relocator.relocate(
                    featureID: stageID,
                    sourceBodyID: bodyID,
                    transform: placement,
                    stablePrefix: "join:placedOperand",
                    context: staged
                )
            }
            stages.apply(moved)
            bodyIDs.append(try stages.publishedBody(of: moved, featureID: featureID, what: "Moving a body to join"))
        }
        return (stages, bodyIDs)
    }
}

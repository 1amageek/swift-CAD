import CADCore
import CADIR

/// The bodies a Boolean sweep feature (Extrude, Revolve) combines with: each target as it was
/// evaluated, or, when it is placed, moved rigidly into the feature's frame first as a staged body,
/// the way a Boolean moves its placed operands.
package struct PlacedBooleanTargetStager: Sendable {
    private let relocator: (any ExactBodyPatternRebuilding)?

    package init(relocator: (any ExactBodyPatternRebuilding)?) {
        self.relocator = relocator
    }

    /// The target bodies in order, with every placed one relocated as a stage of `stages`.
    package func stage(
        _ targets: [BooleanTargetReference],
        featureID: FeatureID,
        stablePrefix: String,
        stages: inout FeatureEvaluationStages,
        what: String
    ) throws -> [BodyID] {
        let tolerance = stages.context.tolerance
        var bodyIDs: [BodyID] = []
        for (ordinal, target) in targets.enumerated() {
            let bodyID = try stages.context.bodyID(generatedBy: target.featureID)
            guard let placement = target.placement else {
                bodyIDs.append(bodyID)
                continue
            }
            guard let relocator else {
                throw KernelError(phase: .evaluation, code: .unsupportedCapability, featureID: featureID,
                                  tolerance: tolerance, message: "This evaluator cannot move a placed \(what) target.")
            }
            try placement.validate(tolerance: tolerance)
            let stageID = featureEvaluationStageID(featureID: featureID, domain: .booleanOperandPlacement, ordinal: UInt64(ordinal))
            let staged = stages.context
            let moved = try FeatureEvaluationBoundary.evaluate(featureID: featureID, tolerance: tolerance) {
                try relocator.relocate(
                    featureID: stageID, sourceBodyID: bodyID, transform: placement,
                    stablePrefix: stablePrefix, context: staged
                )
            }
            stages.apply(moved)
            bodyIDs.append(try stages.publishedBody(of: moved, featureID: featureID, what: "Moving \(what) target"))
        }
        return bodyIDs
    }
}

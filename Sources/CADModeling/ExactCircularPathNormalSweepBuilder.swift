import CADCore
import CADIR

package struct ExactCircularPathNormalSweepBuilder: Sendable {
    private let featureID: FeatureID
    private let context: EvaluationContext
    private let revolveEvaluator: PlanarRevolveFeatureEvaluator

    package init(
        featureID: FeatureID,
        context: EvaluationContext,
        revolveEvaluator: PlanarRevolveFeatureEvaluator
    ) {
        self.featureID = featureID
        self.context = context
        self.revolveEvaluator = revolveEvaluator
    }

    package func build(
        profile: Profile,
        profileReference: ProfileReference,
        path: ExactCircularSweepPath
    ) throws -> EvaluationResult {
        try context.tolerance.validate()
        try path.validateNormalSection(
            plane: profile.plane,
            featureID: featureID,
            tolerance: context.tolerance
        )
        let revolveFeature = FeatureNode(
            id: featureID,
            operation: .revolve(RevolveFeature(
                profile: profileReference,
                axis: path.axis,
                angle: .constant(.angle(path.angle, unit: .radian)),
                operation: .newBody
            )),
            outputs: [FeatureOutput(role: .body)]
        )
        do {
            return try revolveEvaluator.evaluate(
                feature: revolveFeature,
                context: context
            )
        } catch {
            throw KernelError.wrapping(
                error,
                phase: .evaluation,
                featureID: featureID,
                tolerance: context.tolerance
            )
        }
    }

}

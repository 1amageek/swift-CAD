import CADCore
import CADGeometry
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

    package func build(profile: Profile, section: SectionReference,
        path: ExactCircularSweepPath) throws -> EvaluationResult {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try build(profile: profile, section: section, path: path, using: &execution)
    }

    package func build(
        profile: Profile,
        section: SectionReference,
        path: ExactCircularSweepPath
    , using execution: inout OriginalQueryExecution) throws -> EvaluationResult {
        try context.tolerance.validate()
        try path.validateNormalSection(
            plane: profile.plane,
            featureID: featureID,
            tolerance: context.tolerance
        )
        let revolveFeature = FeatureNode(
            id: featureID,
            operation: .revolve(RevolveFeature(
                section: section,
                axis: path.axis,
                angle: .constant(.angle(path.angle, unit: .radian)),
                operation: .newBody,
                resultKind: .solid
            )),
            outputs: [FeatureOutput(role: .body)]
        )
        do {
            return try revolveEvaluator.evaluateValidated(
                feature: revolveFeature, context: context, using: &execution
            ).result
        } catch {
            let classification = OriginalQueryFailure.classification(of: error) ?? KernelError.wrapping(
                error,
                phase: .evaluation,
                featureID: featureID,
                tolerance: context.tolerance
            )
            throw OriginalQueryFailure.contextualizing(
                OriginalQueryFailure.published(error, context: execution.context, tolerance: context.tolerance),
                classification: classification)
        }
    }

}

import CADCore
import CADIR

public struct PatchSurfaceFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let surfaceEvaluator: BSplineSurfaceFeatureEvaluator

    public init(
        surfaceEvaluator: BSplineSurfaceFeatureEvaluator = BSplineSurfaceFeatureEvaluator()
    ) {
        self.surfaceEvaluator = surfaceEvaluator
    }

    public func evaluate(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    package func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        try context.tolerance.validate()
        guard case let .patchSurface(patch) = feature.operation else {
            throw KernelError(
                phase: .evaluation,
                code: .unsupportedCapability,
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "PatchSurfaceFeatureEvaluator requires a patch surface feature."
            )
        }
        guard feature.inputs.isEmpty else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "Patch surface inline boundaries must not declare feature inputs."
            )
        }
        let surface = try patch.surface(tolerance: context.tolerance)
        return try surfaceEvaluator.evaluateValidated(
            feature: FeatureNode(
                id: feature.id,
                name: feature.name,
                operation: .bSplineSurface(BSplineSurfaceFeature(
                    surface: surface,
                    material: patch.material
                )),
                outputs: feature.outputs,
                isSuppressed: feature.isSuppressed
            ),
            context: context
        )
    }
}

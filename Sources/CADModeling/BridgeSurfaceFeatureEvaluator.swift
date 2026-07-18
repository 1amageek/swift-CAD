import CADCore
import CADIR

public struct BridgeSurfaceFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
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
        guard case let .bridgeSurface(bridge) = feature.operation else {
            throw KernelError(
                phase: .evaluation,
                code: .unsupportedCapability,
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "BridgeSurfaceFeatureEvaluator requires a bridge surface feature."
            )
        }
        guard feature.inputs.isEmpty else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "Bridge surface inline boundaries must not declare feature inputs."
            )
        }
        let surface = try bridge.surface(tolerance: context.tolerance)
        return try surfaceEvaluator.evaluateValidated(
            feature: FeatureNode(
                id: feature.id,
                name: feature.name,
                operation: .bSplineSurface(BSplineSurfaceFeature(
                    surface: surface,
                    material: bridge.material
                )),
                outputs: feature.outputs,
                isSuppressed: feature.isSuppressed
            ),
            context: context
        )
    }
}

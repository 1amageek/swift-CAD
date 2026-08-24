import CADCore
import CADGeometry
import CADIR

public struct PatchSurfaceFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let surfaceEvaluator: BSplineSurfaceFeatureEvaluator
    private let surfaceBuilder: any TransfiniteBSplineSurfaceBuilding

    public init(
        surfaceEvaluator: BSplineSurfaceFeatureEvaluator = BSplineSurfaceFeatureEvaluator(),
        surfaceBuilder: any TransfiniteBSplineSurfaceBuilding = ExactCoonsBSplineSurfaceBuilder()
    ) {
        self.surfaceEvaluator = surfaceEvaluator
        self.surfaceBuilder = surfaceBuilder
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
        try FeatureEvaluationBoundary.evaluateValidated(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try evaluateUnvalidated(feature: feature, context: context)
        }
    }

    private func evaluateUnvalidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .patchSurface(patch) = feature.operation else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
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
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try patch.validate(tolerance: context.tolerance)
        }
        let surface = try surfaceBuilder.build(
            vMinimumBoundary: try oriented(
                patch.vMinimumBoundary,
                orientation: patch.vMinimumOrientation,
                tolerance: context.tolerance
            ),
            vMaximumBoundary: try oriented(
                patch.vMaximumBoundary,
                orientation: patch.vMaximumOrientation,
                tolerance: context.tolerance
            ),
            uMinimumBoundary: try oriented(
                patch.uMinimumBoundary,
                orientation: patch.uMinimumOrientation,
                tolerance: context.tolerance
            ),
            uMaximumBoundary: try oriented(
                patch.uMaximumBoundary,
                orientation: patch.uMaximumOrientation,
                tolerance: context.tolerance
            ),
            tolerance: context.tolerance
        )
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
        ).result
    }

    private func oriented(
        _ curve: BSplineCurve3D,
        orientation: PatchSurfaceFeature.BoundaryOrientation,
        tolerance: ModelingTolerance
    ) throws -> BSplineCurve3D {
        switch orientation {
        case .forward:
            return curve
        case .reversed:
            return try curve.reversed(tolerance: tolerance)
        }
    }
}

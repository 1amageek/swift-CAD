import CADCore
import CADGeometry
import CADIR

public struct BridgeSurfaceFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let surfaceEvaluator: BSplineSurfaceFeatureEvaluator
    private let surfaceBuilder: any RuledBSplineSurfaceBuilding

    public init(
        surfaceEvaluator: BSplineSurfaceFeatureEvaluator = BSplineSurfaceFeatureEvaluator(),
        surfaceBuilder: any RuledBSplineSurfaceBuilding = ExactRuledBSplineSurfaceBuilder()
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
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try bridge.validate(tolerance: context.tolerance)
        }
        let endBoundary: BSplineCurve3D
        switch bridge.endOrientation {
        case .forward:
            endBoundary = bridge.endBoundary
        case .reversed:
            endBoundary = try bridge.endBoundary.reversed(
                tolerance: context.tolerance
            )
        }
        let surface = try surfaceBuilder.build(
            startBoundary: bridge.startBoundary,
            endBoundary: endBoundary,
            tolerance: context.tolerance
        )
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
        ).result
    }
}

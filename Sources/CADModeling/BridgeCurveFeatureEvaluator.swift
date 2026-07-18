import CADCore
import CADGeometry
import CADIR

public struct BridgeCurveFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let sampler: any DerivedCurveSampling

    public init(
        sampler: any DerivedCurveSampling = UniformDerivedCurveSampler()
    ) {
        self.sampler = sampler
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
        guard case let .bridgeCurve(bridgeCurve) = feature.operation else {
            throw KernelError(
                phase: .evaluation,
                code: .unsupportedCapability,
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "BridgeCurveFeatureEvaluator requires a bridge curve feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try bridgeCurve.validate(tolerance: context.tolerance)
        }
        let bridgeResult = try CurveBridgeSolver(modelingTolerance: context.tolerance).solve(CurveBridgeRequest(
            start: CurveBridgeEndpointConstraint(
                target: bridgeCurve.start.continuityTarget(),
                requiredLevel: bridgeCurve.start.requiredLevel,
                derivativeMagnitude: bridgeCurve.start.derivativeMagnitude
            ),
            end: CurveBridgeEndpointConstraint(
                target: bridgeCurve.end.continuityTarget(),
                requiredLevel: bridgeCurve.end.requiredLevel,
                derivativeMagnitude: bridgeCurve.end.derivativeMagnitude
            ),
            continuityTolerances: bridgeCurve.continuityTolerances
        ))
        let generatedCurve = try evaluatedCurve(
            featureID: feature.id,
            curve: bridgeResult.curve,
            tolerance: context.tolerance
        )
        return EvaluationResult(
            brep: context.brep,
            generatedCurves: [generatedCurve]
        )
    }

    private func evaluatedCurve(
        featureID: FeatureID,
        curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        let points = try sampler.points(for: curve, tolerance: tolerance)
        let evaluated = EvaluatedCurve(
            sourceFeatureID: featureID,
            source: .generatedFeature,
            kind: .spline,
            points: points,
            exactCurve: .bSpline(curve)
        )
        try evaluated.validate(tolerance: tolerance)
        return evaluated
    }
}

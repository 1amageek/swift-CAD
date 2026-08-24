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
                phase: .validation,
                code: .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "BridgeCurveFeatureEvaluator requires a bridge curve feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try bridgeCurve.validate(tolerance: context.tolerance)
        }
        let startConstraint = try endpointConstraint(
            bridgeCurve.start,
            owner: "start",
            featureID: feature.id,
            context: context
        )
        let endConstraint = try endpointConstraint(
            bridgeCurve.end,
            owner: "end",
            featureID: feature.id,
            context: context
        )
        let bridgeResult = try CurveBridgeSolver(modelingTolerance: context.tolerance).solve(CurveBridgeRequest(
            start: startConstraint,
            end: endConstraint,
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

    private func endpointConstraint(
        _ reference: BridgeCurveEndpointReference,
        owner: String,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> CurveBridgeEndpointConstraint {
        try reference.validate(tolerance: context.tolerance)
        guard let curves = context.curves[reference.curve.featureID],
              reference.curve.curveIndex < curves.count else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                featureID: featureID,
                tolerance: context.tolerance,
                message: "Bridge curve \(owner) curve output could not be resolved."
            )
        }
        let evaluatedCurve = curves[reference.curve.curveIndex]
        try evaluatedCurve.validate(tolerance: context.tolerance)
        guard let exactCurve = evaluatedCurve.exactCurve else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                featureID: featureID,
                tolerance: context.tolerance,
                message: "Bridge curve \(owner) input does not contain exact curve geometry."
            )
        }
        let parameter: Double
        switch evaluatedCurve.parameterDomain {
        case let .closed(lowerBound, upperBound):
            parameter = reference.end == .start ? lowerBound : upperBound
        case .periodic, .unbounded:
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                message: "Bridge curve \(owner) input must have a finite distinguished endpoint."
            )
        }
        return CurveBridgeEndpointConstraint(
            target: CurveContinuityTarget(
                curve: exactCurve,
                parameter: parameter,
                orientation: reference.orientation
            ),
            requiredLevel: reference.requiredLevel,
            derivativeMagnitude: reference.derivativeMagnitude
        )
    }

    private func evaluatedCurve(
        featureID: FeatureID,
        curve: BSplineCurve3D,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        let points = try sampler.points(for: curve, domain: nil, tolerance: tolerance)
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

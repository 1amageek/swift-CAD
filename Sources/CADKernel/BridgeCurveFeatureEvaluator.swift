import CADCore
import CADIR

public struct BridgeCurveFeatureEvaluator: FeatureEvaluating {
    private let solver: CurveBridgeSolver

    public init(solver: CurveBridgeSolver = CurveBridgeSolver()) {
        self.solver = solver
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .bridgeCurve(bridgeCurve) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("BridgeCurveFeatureEvaluator requires a bridge curve feature.")
        }
        try bridgeCurve.validate(tolerance: context.tolerance)
        let bridgeResult = try solver.solve(CurveBridgeRequest(
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
            sampleCount: bridgeCurve.sampleCount,
            tolerance: context.tolerance
        )
        return EvaluationResult(
            brep: context.brep,
            generatedNames: [:],
            generatedCurves: [generatedCurve]
        )
    }

    private func evaluatedCurve(
        featureID: FeatureID,
        curve: BSplineCurve3D,
        sampleCount: Int,
        tolerance: ModelingTolerance
    ) throws -> EvaluatedCurve {
        guard sampleCount >= 2 else {
            throw GeometryError.invalidDistance(Double(sampleCount))
        }
        let points = try (0..<sampleCount).map { index in
            try curve.point(
                at: Double(index) / Double(sampleCount - 1),
                tolerance: tolerance
            )
        }
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

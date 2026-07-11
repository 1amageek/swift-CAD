import CADCore
import CADIR

public struct DefaultFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let extrudeEvaluator: PlanarExtrudeFeatureEvaluator
    private let revolveEvaluator: PlanarRevolveFeatureEvaluator
    private let sweepEvaluator: PlanarSweepFeatureEvaluator
    private let loftEvaluator: LoftFeatureEvaluator
    private let booleanEvaluator: BooleanFeatureEvaluator
    private let polySplineEvaluator: PolySplineFeatureEvaluator
    private let bSplineSurfaceEvaluator: BSplineSurfaceFeatureEvaluator
    private let faceLoopOffsetEvaluator: FaceLoopOffsetFeatureEvaluator
    private let edgeOffsetEvaluator: EdgeOffsetFeatureEvaluator
    private let faceKnifeEvaluator: FaceKnifeFeatureEvaluator
    private let faceDeleteEvaluator: FaceDeleteFeatureEvaluator
    private let faceDraftEvaluator: FaceDraftFeatureEvaluator
    private let bridgeCurveEvaluator: BridgeCurveFeatureEvaluator
    private let curveEditEvaluator: CurveEditFeatureEvaluator
    private let curveOffsetEvaluator: CurveOffsetFeatureEvaluator
    private let curveTrimEvaluator: CurveTrimFeatureEvaluator

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.extrudeEvaluator = PlanarExtrudeFeatureEvaluator(resolver: resolver)
        self.revolveEvaluator = PlanarRevolveFeatureEvaluator(resolver: resolver)
        self.sweepEvaluator = PlanarSweepFeatureEvaluator(
            resolver: resolver,
            extrudeEvaluator: extrudeEvaluator
        )
        self.loftEvaluator = LoftFeatureEvaluator()
        self.booleanEvaluator = BooleanFeatureEvaluator()
        self.polySplineEvaluator = PolySplineFeatureEvaluator()
        self.bSplineSurfaceEvaluator = BSplineSurfaceFeatureEvaluator()
        self.faceLoopOffsetEvaluator = FaceLoopOffsetFeatureEvaluator(resolver: resolver)
        self.edgeOffsetEvaluator = EdgeOffsetFeatureEvaluator(resolver: resolver)
        self.faceKnifeEvaluator = FaceKnifeFeatureEvaluator()
        self.faceDeleteEvaluator = FaceDeleteFeatureEvaluator()
        self.faceDraftEvaluator = FaceDraftFeatureEvaluator(resolver: resolver)
        self.bridgeCurveEvaluator = BridgeCurveFeatureEvaluator()
        self.curveEditEvaluator = CurveEditFeatureEvaluator()
        self.curveOffsetEvaluator = CurveOffsetFeatureEvaluator(resolver: resolver)
        self.curveTrimEvaluator = CurveTrimFeatureEvaluator()
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        try evaluateValidated(feature: feature, context: context).result
    }

    func evaluateValidated(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> ValidatedFeatureEvaluation {
        switch feature.operation {
        case .sketch:
            throw FeatureEvaluationError.unsupportedOperation("Sketch features do not produce BRep bodies directly.")
        case .extrude:
            return try extrudeEvaluator.evaluateValidated(feature: feature, context: context)
        case .revolve:
            return try validated(
                revolveEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .sweep:
            return try validated(
                sweepEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .loft:
            return try validated(
                loftEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .boolean:
            return try validated(
                booleanEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .polySpline:
            return try validated(
                polySplineEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .bSplineSurface:
            return try validated(
                bSplineSurfaceEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .faceLoopOffset:
            return try validated(
                faceLoopOffsetEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .edgeOffset:
            return try validated(
                edgeOffsetEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .faceKnife:
            return try validated(
                faceKnifeEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .faceDelete:
            return try validated(
                faceDeleteEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .faceDraft:
            return try validated(
                faceDraftEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .bridgeCurve:
            return try validated(
                bridgeCurveEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .curveEdit:
            return try validated(
                curveEditEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .curveOffset:
            return try validated(
                curveOffsetEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        case .curveTrim:
            return try validated(
                curveTrimEvaluator.evaluate(feature: feature, context: context),
                tolerance: context.tolerance
            )
        }
    }

    private func validated(
        _ result: EvaluationResult,
        tolerance: ModelingTolerance
    ) throws -> ValidatedFeatureEvaluation {
        try ValidatedFeatureEvaluation(validating: result, tolerance: tolerance)
    }
}

import CADCore
import CADIR

public struct DefaultFeatureEvaluator: FeatureEvaluating {
    private let extrudeEvaluator: PlanarExtrudeFeatureEvaluator
    private let revolveEvaluator: PlanarRevolveFeatureEvaluator
    private let sweepEvaluator: PlanarSweepFeatureEvaluator
    private let loftEvaluator: PlanarLoftFeatureEvaluator
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
        self.loftEvaluator = PlanarLoftFeatureEvaluator()
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
        switch feature.operation {
        case .sketch:
            throw FeatureEvaluationError.unsupportedOperation("Sketch features do not produce BRep bodies directly.")
        case .extrude:
            return try extrudeEvaluator.evaluate(feature: feature, context: context)
        case .revolve:
            return try revolveEvaluator.evaluate(feature: feature, context: context)
        case .sweep:
            return try sweepEvaluator.evaluate(feature: feature, context: context)
        case .loft:
            return try loftEvaluator.evaluate(feature: feature, context: context)
        case .boolean:
            return try booleanEvaluator.evaluate(feature: feature, context: context)
        case .polySpline:
            return try polySplineEvaluator.evaluate(feature: feature, context: context)
        case .bSplineSurface:
            return try bSplineSurfaceEvaluator.evaluate(feature: feature, context: context)
        case .faceLoopOffset:
            return try faceLoopOffsetEvaluator.evaluate(feature: feature, context: context)
        case .edgeOffset:
            return try edgeOffsetEvaluator.evaluate(feature: feature, context: context)
        case .faceKnife:
            return try faceKnifeEvaluator.evaluate(feature: feature, context: context)
        case .faceDelete:
            return try faceDeleteEvaluator.evaluate(feature: feature, context: context)
        case .faceDraft:
            return try faceDraftEvaluator.evaluate(feature: feature, context: context)
        case .bridgeCurve:
            return try bridgeCurveEvaluator.evaluate(feature: feature, context: context)
        case .curveEdit:
            return try curveEditEvaluator.evaluate(feature: feature, context: context)
        case .curveOffset:
            return try curveOffsetEvaluator.evaluate(feature: feature, context: context)
        case .curveTrim:
            return try curveTrimEvaluator.evaluate(feature: feature, context: context)
        }
    }
}

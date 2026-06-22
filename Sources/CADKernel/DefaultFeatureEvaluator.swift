import CADCore
import CADIR

public struct DefaultFeatureEvaluator: FeatureEvaluating {
    private let extrudeEvaluator: PlanarExtrudeFeatureEvaluator
    private let sweepEvaluator: PlanarSweepFeatureEvaluator
    private let polySplineEvaluator: PolySplineFeatureEvaluator
    private let faceLoopOffsetEvaluator: FaceLoopOffsetFeatureEvaluator
    private let edgeOffsetEvaluator: EdgeOffsetFeatureEvaluator
    private let faceKnifeEvaluator: FaceKnifeFeatureEvaluator

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.extrudeEvaluator = PlanarExtrudeFeatureEvaluator(resolver: resolver)
        self.sweepEvaluator = PlanarSweepFeatureEvaluator(
            resolver: resolver,
            extrudeEvaluator: extrudeEvaluator
        )
        self.polySplineEvaluator = PolySplineFeatureEvaluator()
        self.faceLoopOffsetEvaluator = FaceLoopOffsetFeatureEvaluator(resolver: resolver)
        self.edgeOffsetEvaluator = EdgeOffsetFeatureEvaluator(resolver: resolver)
        self.faceKnifeEvaluator = FaceKnifeFeatureEvaluator()
    }

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        switch feature.operation {
        case .sketch:
            throw FeatureEvaluationError.unsupportedOperation("Sketch features do not produce BRep bodies directly.")
        case .extrude:
            return try extrudeEvaluator.evaluate(feature: feature, context: context)
        case .sweep:
            return try sweepEvaluator.evaluate(feature: feature, context: context)
        case .polySpline:
            return try polySplineEvaluator.evaluate(feature: feature, context: context)
        case .faceLoopOffset:
            return try faceLoopOffsetEvaluator.evaluate(feature: feature, context: context)
        case .edgeOffset:
            return try edgeOffsetEvaluator.evaluate(feature: feature, context: context)
        case .faceKnife:
            return try faceKnifeEvaluator.evaluate(feature: feature, context: context)
        }
    }
}

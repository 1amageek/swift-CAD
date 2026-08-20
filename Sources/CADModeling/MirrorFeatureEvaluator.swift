import CADCore
import CADIR

public struct MirrorFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let rebuilder: any ExactPlanarPatternRebuilding

    public init(sewer: any BRepSewing) {
        self.rebuilder = DefaultExactPlanarPatternRebuilder(sewer: sewer)
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
        guard case let .mirror(mirror) = feature.operation else {
            throw error(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Mirror evaluator requires a mirror feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try mirror.validate(tolerance: context.tolerance)
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let bodyID = try targetBodyID(mirror.target.featureID, featureID: feature.id, context: context)
        let transforms: [ExactPatternTransform] = [
            .translated(by: .zero),
            try .mirrored(
                across: mirror.planeOrigin,
                normal: mirror.planeNormal,
                tolerance: context.tolerance
            ),
        ]
        return try rebuilder.rebuild(
            featureID: feature.id,
            sourceBodyID: bodyID,
            transforms: transforms,
            stablePrefix: "mirror",
            context: context
        )
    }

    private func targetBodyID(
        _ sourceFeatureID: FeatureID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: sourceFeatureID)
    }

    private func error(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}

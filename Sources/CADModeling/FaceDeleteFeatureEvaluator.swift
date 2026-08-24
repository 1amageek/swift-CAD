import CADCore
import CADIR
import CADTopology

public struct FaceDeleteFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let subshapeResolver: any StableSubshapeResolving
    private let topologyTransformer: any FaceDeletionTopologyTransforming
    private let identityBuilder: any CarriedTopologyIdentityBuilding

    public init(
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver(),
        topologyTransformer: any FaceDeletionTopologyTransforming = DefaultFaceDeletionTopologyTransformer()
    ) {
        self.subshapeResolver = subshapeResolver
        self.topologyTransformer = topologyTransformer
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
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
            try evaluateFaceDelete(feature: feature, context: context)
        }
    }

    private func evaluateFaceDelete(
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        guard case let .faceDelete(faceDelete) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Face delete evaluator requires a faceDelete feature."
            )
        }
        try faceDelete.validate()
        try FeatureEvaluationBoundary.validateExactInput(
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )

        let bodyID = try targetBodyID(for: faceDelete.target.featureID, context: context)
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        var resolvedFaceIDs = Set<FaceID>()
        for stableReference in faceDelete.faces {
            let faceID = try targetFaceID(for: stableReference, featureID: feature.id, context: context)
            guard resolvedFaceIDs.insert(faceID).inserted else {
                throw kernelError(
                    .invalidInput,
                    featureID: feature.id,
                    subshapeID: stableReference.subshapeID,
                    tolerance: context.tolerance,
                    "Face delete selections resolve to the same face."
                )
            }
        }

        let model = try topologyTransformer.transformedModel(
            deleting: resolvedFaceIDs,
            from: bodyID,
            featureID: feature.id,
            in: context.brep,
            tolerance: context.tolerance
        )
        try model.validate(level: .exact, tolerance: context.tolerance)

        let identity = try identityBuilder.identity(
            featureID: feature.id,
            bodyID: bodyID,
            model: model,
            context: context
        )
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: identity.lineage
        )
    }

    private func targetBodyID(
        for featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: featureID)
    }

    private func targetFaceID(
        for stableReference: StableSubshapeReference,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> FaceID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .face(faceID) = reference else {
            throw kernelError(
                .missingReference,
                featureID: featureID,
                subshapeID: stableReference.subshapeID,
                tolerance: context.tolerance,
                "Face delete target did not resolve to a face."
            )
        }
        return faceID
    }

    private func kernelError(
        _ code: KernelErrorCode,
        featureID: FeatureID,
        subshapeID: SubshapeID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            subshapeID: subshapeID,
            tolerance: tolerance,
            message: message
        )
    }

}

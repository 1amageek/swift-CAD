import CADCore
import CADIR
import CADTopology

public struct FaceOffsetFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding
    private let translator: PlanarFaceTranslator

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
        translator = PlanarFaceTranslator()
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
        try FeatureEvaluationBoundary.evaluateValidated(featureID: feature.id, tolerance: context.tolerance) {
            try evaluateFaceOffset(feature: feature, context: context)
        }
    }

    private func evaluateFaceOffset(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .faceOffset(offset) = feature.operation else {
            throw kernelError(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Face offset evaluator requires a faceOffset feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try offset.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let distance = try resolvedDistance(offset.distance, featureID: feature.id, context: context)
        let bodyID = try context.bodyID(generatedBy: offset.target.featureID)
        let bodyScope = try BodyTopologyScope(bodyID: bodyID, model: context.brep)
        let faceID = try targetFaceID(
            offset.face,
            bodyScope: bodyScope,
            featureID: feature.id,
            context: context
        )
        let replacedSubshapeIDs = bodyScope.subshapeIDs(in: context.subshapes)
        var model = context.brep
        let normal = try translator.outwardNormal(
            faceID: faceID,
            bodyID: bodyID,
            featureID: feature.id,
            model: model,
            tolerance: context.tolerance
        )
        // The face moves along its outward normal; only the faces around it are re-solved, as
        // planes, bilinear patches where a quad warps, or cylinders sliding along their axis.
        guard let face = model.faces[faceID] else {
            throw TopologyError.missingReference("Face offset face is missing.")
        }
        var vertexIDs = Set<VertexID>()
        for loopID in face.loops { vertexIDs.formUnion(try model.orderedVertexIDs(for: loopID)) }
        let displacement = normal * distance
        try LocalVertexDisplacementRebuilder().displace(
            Dictionary(uniqueKeysWithValues: vertexIDs.map { ($0, displacement) }),
            bodyID: bodyID, featureID: feature.id, model: &model, tolerance: context.tolerance
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: context.tolerance)
        let isSolid = model.bodies[bodyID]?.kind == .solid
        try model.validate(level: isSolid ? .volumetric : .exact, tolerance: context.tolerance)
        let identity = try identityBuilder.identity(featureID: feature.id, bodyID: bodyID, model: model, context: context)
        return EvaluationResult(
            brep: model,
            subshapes: identity.subshapes,
            removedSubshapeIDs: replacedSubshapeIDs,
            lineage: identity.lineage
        )
    }

    private func resolvedDistance(
        _ expression: CADExpression,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: "faceOffset.distance", expected: .length, actual: quantity.kind)
        }
        guard quantity.value.isFinite, abs(quantity.value) > context.tolerance.distance else {
            throw kernelError(.invalidInput, featureID: featureID, tolerance: context.tolerance, "Face offset distance must be finite and larger than modeling tolerance.")
        }
        return quantity.value
    }

    private func targetFaceID(
        _ stableReference: StableSubshapeReference,
        bodyScope: BodyTopologyScope,
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
            throw kernelError(.missingReference, featureID: featureID, subshapeID: stableReference.subshapeID, tolerance: context.tolerance, "Face offset target face could not be resolved.")
        }
        guard bodyScope.references.contains(.face(faceID)) else {
            throw kernelError(
                .missingReference,
                featureID: featureID,
                subshapeID: stableReference.subshapeID,
                tolerance: context.tolerance,
                "Face offset target face does not belong to the target body."
            )
        }
        return faceID
    }

    private func kernelError(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
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

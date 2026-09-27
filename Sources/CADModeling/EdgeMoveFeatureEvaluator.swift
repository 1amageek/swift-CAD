import CADCore
import CADIR
import CADTopology

public struct EdgeMoveFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
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
            try evaluateEdgeMove(feature: feature, context: context)
        }
    }

    private func evaluateEdgeMove(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .edgeMove(move) = feature.operation else {
            throw error(.invalidInput, featureID: feature.id, tolerance: context.tolerance, "Edge move evaluator requires an edgeMove feature.")
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try move.validate(tolerance: context.tolerance)
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let distance = try resolvedDistance(move.translation.distance, featureID: feature.id, context: context)
        let direction = try move.translation.direction.normalized(tolerance: context.tolerance.distance)
        let bodyID = try targetBodyID(move.target.featureID, featureID: feature.id, context: context)
        let bodyScope = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        )
        let edgeID = try targetEdgeID(
            move.edge,
            bodyScope: bodyScope,
            featureID: feature.id,
            context: context
        )
        let replacedSubshapeIDs = bodyScope.subshapeIDs(in: context.subshapes)
        var model = context.brep
        let isCircular: Bool
        if let edge = model.edges[edgeID], case .circle = model.geometry.curves[edge.curveID] {
            isCircular = true
        } else {
            isCircular = false
        }
        if isCircular {
            // A circular edge moves along its axis with the flat face it bounds, keeping the
            // analytic surfaces around it; solids and sheets alike.
            try CircularEdgeCapTranslator().translate(
                capBoundedBy: edgeID,
                bodyID: bodyID,
                displacement: direction * distance,
                featureID: feature.id,
                model: &model,
                tolerance: context.tolerance
            )
        } else {
            // A straight edge moves its two ends; only the faces around it are re-solved, as
            // planes or, where a four-sided face warps, as the bilinear patch of its corners.
            guard let edge = model.edges[edgeID], case .line = model.geometry.curves[edge.curveID] else {
                throw error(.unsupportedCapability, featureID: feature.id, tolerance: context.tolerance,
                            "Edge move requires a straight or circular edge on the target body.")
            }
            let displacement = direction * distance
            try LocalVertexDisplacementRebuilder().displace(
                [edge.startVertexID: displacement, edge.endVertexID: displacement],
                bodyID: bodyID,
                featureID: feature.id,
                model: &model,
                tolerance: context.tolerance
            )
        }
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: context.tolerance)
        let isSolid = model.bodies[bodyID]?.kind == .solid
        try model.validate(level: isSolid ? .volumetric : .exact, tolerance: context.tolerance)
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

    private func resolvedDistance(
        _ expression: CADExpression,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: "edgeMove.distance", expected: .length, actual: quantity.kind)
        }
        guard quantity.value.isFinite,
              abs(quantity.value) > context.tolerance.distance else {
            throw error(.invalidInput, featureID: featureID, tolerance: context.tolerance, "Edge move distance must be finite and larger than modeling tolerance.")
        }
        return quantity.value
    }

    private func targetBodyID(
        _ sourceFeatureID: FeatureID,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> BodyID {
        try context.bodyID(generatedBy: sourceFeatureID)
    }

    private func targetEdgeID(
        _ stableReference: StableSubshapeReference,
        bodyScope: BodyTopologyScope,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> EdgeID {
        let reference = try subshapeResolver.topologyReference(
            for: stableReference,
            model: context.brep,
            subshapes: context.subshapes,
            lineage: context.lineage,
            tolerance: context.tolerance
        )
        guard case let .edge(edgeID) = reference else {
            throw error(
                .missingReference,
                featureID: featureID,
                subshapeID: stableReference.subshapeID,
                tolerance: context.tolerance,
                "Edge move target edge could not be resolved."
            )
        }
        guard bodyScope.references.contains(.edge(edgeID)) else {
            throw error(
                .missingReference,
                featureID: featureID,
                subshapeID: stableReference.subshapeID,
                tolerance: context.tolerance,
                "Edge move target edge does not belong to the target body."
            )
        }
        return edgeID
    }

    private func error(
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

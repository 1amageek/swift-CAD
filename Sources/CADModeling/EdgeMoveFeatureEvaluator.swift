import CADCore
import CADIR
import CADTopology

public struct EdgeMoveFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let subshapeResolver: any StableSubshapeResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding
    private let geometryRebuilder: any PlanarBodyGeometryRebuilding

    public init(
        resolver: ParameterResolving = ParameterResolver(),
        subshapeResolver: any StableSubshapeResolving = StableSubshapeResolver()
    ) {
        self.resolver = resolver
        self.subshapeResolver = subshapeResolver
        identityBuilder = DefaultCarriedTopologyIdentityBuilder()
        geometryRebuilder = DefaultPlanarBodyGeometryRebuilder()
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
        try translateEdge(
            edgeID,
            bodyID: bodyID,
            displacement: direction * distance,
            featureID: feature.id,
            model: &model,
            tolerance: context.tolerance
        )
        try geometryRebuilder.rebuild(
            featureID: feature.id,
            bodyID: bodyID,
            in: &model,
            tolerance: context.tolerance
        )
        try ExactFacePcurveBuilder().populateMissingPcurves(in: &model, tolerance: context.tolerance)
        try model.validate(level: .volumetric, tolerance: context.tolerance)
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

    private func translateEdge(
        _ edgeID: EdgeID,
        bodyID: BodyID,
        displacement: Vector3D,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        guard let body = model.bodies[bodyID], body.kind == .solid else {
            throw error(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Edge move currently requires one solid body.")
        }
        let bodyEdgeIDs = try body.shellIDs.reduce(into: Set<EdgeID>()) { result, shellID in
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Edge move shell is missing.")
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Edge move face is missing.")
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Edge move loop is missing.")
                    }
                    result.formUnion(loop.coedges.map(\.edgeID))
                }
            }
        }
        guard bodyEdgeIDs.contains(edgeID),
              let edge = model.edges[edgeID],
              case .line = model.geometry.curves[edge.curveID] else {
            throw error(.unsupportedCapability, featureID: featureID, tolerance: tolerance, "Edge move requires one straight edge on the target body.")
        }
        for vertexID in [edge.startVertexID, edge.endVertexID] {
            guard var vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Edge move vertex is missing.")
            }
            vertex.point = vertex.point + displacement
            try vertex.point.validate()
            model.vertices[vertexID] = vertex
        }
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

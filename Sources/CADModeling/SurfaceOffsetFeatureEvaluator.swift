import CADCore
import CADIR
import CADTopology

public struct SurfaceOffsetFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let identityBuilder: any CarriedTopologyIdentityBuilding
    private let geometryRebuilder: any PlanarBodyGeometryRebuilding

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
        self.identityBuilder = DefaultCarriedTopologyIdentityBuilder()
        self.geometryRebuilder = DefaultPlanarBodyGeometryRebuilder()
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
        guard case let .surfaceOffset(offset) = feature.operation else {
            throw kernelError(
                .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                "Surface offset evaluator requires a surfaceOffset feature."
            )
        }
        try FeatureEvaluationBoundary.validateRequest(featureID: feature.id, tolerance: context.tolerance) {
            try offset.validate()
        }
        try FeatureEvaluationBoundary.validateExactInput(
            context.brep,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let distance = try resolvedDistance(offset.distance, featureID: feature.id, context: context)
        let bodyID = try targetBodyID(offset.target.featureID, featureID: feature.id, context: context)
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        var model = context.brep
        try translatePlanarSheet(
            bodyID: bodyID,
            distance: distance,
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

    private func resolvedDistance(
        _ expression: CADExpression,
        featureID: FeatureID,
        context: EvaluationContext
    ) throws -> Double {
        let quantity = try resolver.evaluate(expression, parameters: context.parameters, variables: [:])
        guard quantity.kind == .length else {
            throw UnitError.expectedQuantity(operation: "surfaceOffset.distance", expected: .length, actual: quantity.kind)
        }
        guard quantity.value.isFinite,
              abs(quantity.value) > context.tolerance.distance else {
            throw kernelError(
                .invalidInput,
                featureID: featureID,
                tolerance: context.tolerance,
                "Surface offset distance must be a finite signed length above modeling tolerance."
            )
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

    private func translatePlanarSheet(
        bodyID: BodyID,
        distance: Double,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        guard let body = model.bodies[bodyID],
              body.kind == .sheet,
              body.shellIDs.count == 1,
              let shellID = body.shellIDs.first,
              let shell = model.shells[shellID],
              shell.faceIDs.count == 1,
              let faceID = shell.faceIDs.first,
              let face = model.faces[faceID],
              case let .plane(plane) = model.geometry.surfaces[face.surfaceID] else {
            throw kernelError(
                .unsupportedCapability,
                featureID: featureID,
                tolerance: tolerance,
                "Exact surface offset currently requires one single-face planar sheet body."
            )
        }
        var vertexIDs = Set<VertexID>()
        for loopID in face.loops {
            guard let loop = model.loops[loopID], loop.role == .outer else {
                throw kernelError(
                    .unsupportedCapability,
                    featureID: featureID,
                    tolerance: tolerance,
                    "Exact surface offset currently requires outer line loops without holes."
                )
            }
            for coedge in loop.coedges {
                guard let edge = model.edges[coedge.edgeID],
                      case .line = model.geometry.curves[edge.curveID] else {
                    throw kernelError(
                        .unsupportedCapability,
                        featureID: featureID,
                        tolerance: tolerance,
                        "Exact surface offset currently requires straight sheet boundaries."
                    )
                }
                vertexIDs.insert(edge.startVertexID)
                vertexIDs.insert(edge.endVertexID)
            }
        }
        let normal = face.orientation == .forward ? plane.normal : -plane.normal
        let translation = normal * distance
        for vertexID in vertexIDs {
            guard var vertex = model.vertices[vertexID] else {
                throw TopologyError.missingReference("Surface offset sheet vertex is missing.")
            }
            vertex.point = vertex.point + translation
            try vertex.point.validate()
            model.vertices[vertexID] = vertex
        }
    }

    private func kernelError(
        _ code: KernelErrorCode,
        featureID: FeatureID? = nil,
        tolerance: ModelingTolerance,
        _ message: String
    ) -> KernelError {
        KernelError(
            phase: code == .topologyFailure ? .topology : .evaluation,
            code: code,
            featureID: featureID,
            tolerance: tolerance,
            message: message
        )
    }
}

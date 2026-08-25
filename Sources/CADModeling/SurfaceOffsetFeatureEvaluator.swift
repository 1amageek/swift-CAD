import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct SurfaceOffsetFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private let resolver: ParameterResolving
    private let targetResolver: any SurfaceOperationTargetResolving
    private let targetValidator: any SingleFaceSheetSurfaceOperationTargetValidating
    private let identityBuilder: any CarriedTopologyIdentityBuilding

    public init(resolver: ParameterResolving = ParameterResolver()) {
        self.resolver = resolver
        self.targetResolver = DefaultSurfaceOperationTargetResolver()
        self.targetValidator = DefaultSingleFaceSheetSurfaceOperationTargetValidator()
        self.identityBuilder = DefaultCarriedTopologyIdentityBuilder()
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
            context,
            featureID: feature.id,
            tolerance: context.tolerance
        )
        let distance = try resolvedDistance(offset.distance, featureID: feature.id, context: context)
        let target = try targetResolver.resolve(
            offset.target,
            featureID: feature.id,
            context: context
        )
        let bodyID = target.bodyID
        let replacedSubshapeIDs = try BodyTopologyScope(
            bodyID: bodyID,
            model: context.brep
        ).subshapeIDs(in: context.subshapes)
        var model = context.brep
        try offsetSingleFaceSheet(
            target: target,
            distance: distance,
            featureID: feature.id,
            model: &model,
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

    private struct BoundaryUse {
        let loopID: LoopID
        let coedgeIndex: Int
        let coedge: Coedge
        let sourceParameterCurve: SurfaceParameterCurve
    }

    private func offsetSingleFaceSheet(
        target: ResolvedSurfaceOperationTarget,
        distance: Double,
        featureID: FeatureID,
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws {
        try targetValidator.validate(
            target,
            operation: "Surface offset",
            featureID: featureID,
            tolerance: tolerance
        )
        let boundaryUses = try collectBoundaryUses(
            face: target.face,
            model: model
        )
        let parameterBounds = try ExactSurfaceParameterBoundsResolver().resolve(
            parameterCurves: boundaryUses.map(\.sourceParameterCurve),
            on: target.surface,
            tolerance: tolerance
        )
        let orientationSign = target.face.orientation == .forward ? 1.0 : -1.0
        let proceduralOffset = OffsetSurface3D(
            source: target.surface,
            distance: distance * orientationSign
        )
        let targetSurface = try proceduralOffset.exactChartPreservingSurface(
            tolerance: tolerance
        ) ?? .procedural(.offset(proceduralOffset))
        try DefaultSurfaceRegularityValidator().validate(
            targetSurface,
            over: parameterBounds,
            tolerance: tolerance
        )

        var topologyIDs = FeatureTopologyIDAllocator(featureID: featureID)
        let surfaceID = nextAvailableSurfaceID(
            model: model,
            topologyIDs: &topologyIDs
        )
        model.geometry.surfaces[surfaceID] = targetSurface
        var face = target.face
        face.surfaceID = surfaceID
        model.faces[target.faceID] = face

        var firstUseByEdge: [EdgeID: BoundaryUse] = [:]
        for use in boundaryUses where firstUseByEdge[use.coedge.edgeID] == nil {
            firstUseByEdge[use.coedge.edgeID] = use
        }
        var vertexCandidates: [VertexID: [Point3D]] = [:]
        for edgeID in firstUseByEdge.keys.sorted() {
            guard let use = firstUseByEdge[edgeID],
                  var edge = model.edges[edgeID] else {
                throw TopologyError.missingReference(
                    "Surface offset boundary edge is missing."
                )
            }
            let canonicalSource = use.coedge.orientation == .forward
                ? use.sourceParameterCurve
                : try use.sourceParameterCurve.reversed(tolerance: tolerance)
            let canonicalTarget = try transported(
                canonicalSource,
                through: proceduralOffset,
                tolerance: tolerance
            )
            let lift = SurfaceLiftCurve3D(
                surface: targetSurface,
                parameterCurve: canonicalTarget
            )
            try lift.validate(tolerance: tolerance)
            let start = try lift.point(
                atNormalizedFraction: 0.0,
                tolerance: tolerance
            )
            let end = try lift.point(
                atNormalizedFraction: 1.0,
                tolerance: tolerance
            )
            vertexCandidates[edge.startVertexID, default: []].append(start)
            vertexCandidates[edge.endVertexID, default: []].append(end)
            let curveID = nextAvailableCurveID(
                model: model,
                topologyIDs: &topologyIDs
            )
            model.geometry.curves[curveID] = .surfaceLift(lift)
            edge.curveID = curveID
            edge.trim = CurveTrim(startParameter: 0.0, endParameter: 1.0)
            model.edges[edgeID] = edge
        }

        for use in boundaryUses {
            guard var loop = model.loops[use.loopID] else {
                throw TopologyError.missingReference(
                    "Surface offset boundary loop is missing."
                )
            }
            loop.coedges[use.coedgeIndex].surfaceParameterCurve = try transported(
                use.sourceParameterCurve,
                through: proceduralOffset,
                tolerance: tolerance
            )
            model.loops[use.loopID] = loop
        }
        for vertexID in vertexCandidates.keys.sorted() {
            guard var vertex = model.vertices[vertexID],
                  let candidates = vertexCandidates[vertexID],
                  let point = candidates.first else {
                throw TopologyError.missingReference(
                    "Surface offset sheet vertex is missing."
                )
            }
            for candidate in candidates.dropFirst() {
                let residual = (candidate - point).length
                guard residual <= tolerance.distance else {
                    throw kernelError(
                        .topologyFailure,
                        featureID: featureID,
                        tolerance: tolerance,
                        "Offset boundary curves disagree at a shared vertex."
                    )
                }
            }
            vertex.point = point
            model.vertices[vertexID] = vertex
        }
        pruneUnreferencedGeometry(in: &model)
    }

    private func collectBoundaryUses(
        face: Face,
        model: BRepModel
    ) throws -> [BoundaryUse] {
        var result: [BoundaryUse] = []
        for loopID in face.loops {
            guard let loop = model.loops[loopID],
                  loop.coedges.isEmpty == false else {
                throw TopologyError.missingReference(
                    "Surface offset face boundary is missing."
                )
            }
            for (coedgeIndex, coedge) in loop.coedges.enumerated() {
                guard model.edges[coedge.edgeID] != nil,
                      let parameterCurve = coedge.surfaceParameterCurve else {
                    throw TopologyError.missingReference(
                        "Surface offset requires an exact pcurve on every boundary coedge."
                    )
                }
                result.append(BoundaryUse(
                    loopID: loopID,
                    coedgeIndex: coedgeIndex,
                    coedge: coedge,
                    sourceParameterCurve: parameterCurve
                ))
            }
        }
        return result
    }

    private func transported(
        _ curve: SurfaceParameterCurve,
        through offset: OffsetSurface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        .offsetSurfaceImage(try offset.parameterCurveImage(
            transporting: curve,
            tolerance: tolerance
        ))
    }

    private func nextAvailableCurveID(
        model: BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) -> CurveID {
        while true {
            let id = topologyIDs.nextCurveID()
            if model.geometry.curves[id] == nil { return id }
        }
    }

    private func nextAvailableSurfaceID(
        model: BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator
    ) -> SurfaceID {
        while true {
            let id = topologyIDs.nextSurfaceID()
            if model.geometry.surfaces[id] == nil { return id }
        }
    }

    private func pruneUnreferencedGeometry(in model: inout BRepModel) {
        let curveIDs = Set(model.edges.values.map(\.curveID))
        model.geometry.curves = model.geometry.curves.filter {
            curveIDs.contains($0.key)
        }
        let surfaceIDs = Set(model.faces.values.map(\.surfaceID))
        model.geometry.surfaces = model.geometry.surfaces.filter {
            surfaceIDs.contains($0.key)
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

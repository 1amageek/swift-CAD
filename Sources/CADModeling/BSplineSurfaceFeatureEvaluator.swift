import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct BSplineSurfaceFeatureEvaluator: FeatureEvaluating, ValidatedFeatureEvaluating {
    private struct BuiltTrimLoop {
        var loopID: LoopID
        var edgeIDs: [EdgeID]
        var vertexIDs: [VertexID]
    }

    private struct BoundaryEdge {
        let parameterCurve: SurfaceParameterCurve
    }

    private struct BoundaryCurveGeometry {
        let curve: Curve3D
        let trim: CurveTrim
    }

    public init() {}

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
        guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw KernelError(
                phase: .evaluation,
                code: .invalidInput,
                featureID: feature.id,
                tolerance: context.tolerance,
                message: "B-spline surface evaluator requires a B-spline surface feature."
            )
        }
        guard feature.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("B-spline surface source features must not declare inputs.")
        }
        try FeatureEvaluationBoundary.validateRequest(
            featureID: feature.id,
            tolerance: context.tolerance
        ) {
            try surfaceFeature.validate(tolerance: context.tolerance)
        }
        return try buildSheetBody(
            surfaceFeature: surfaceFeature,
            feature: feature,
            context: context
        )
    }

    private func buildSheetBody(
        surfaceFeature: BSplineSurfaceFeature,
        feature: FeatureNode,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        var model = context.brep
        let surface = surfaceFeature.surface
        let surfaceGeometry = Surface3D.bSpline(surface)
        let parameterDomain = try surfaceFeature.resolvedParameterDomain(
            tolerance: context.tolerance
        )
        try BSplineSurfaceRegularityValidator().validate(
            surface,
            uDomain: .closed(parameterDomain.uLowerBound, parameterDomain.uUpperBound),
            vDomain: .closed(parameterDomain.vLowerBound, parameterDomain.vUpperBound),
            tolerance: context.tolerance
        )
        try BSplineSurfaceEmbeddingValidator().validate(
            surface,
            uDomain: .closed(parameterDomain.uLowerBound, parameterDomain.uUpperBound),
            vDomain: .closed(parameterDomain.vLowerBound, parameterDomain.vUpperBound),
            tolerance: context.tolerance
        )
        var topologyIDs = FeatureTopologyIDAllocator(featureID: feature.id)
        let bodyID = topologyIDs.nextBodyID()
        let shellID = topologyIDs.nextShellID()
        let faceID = topologyIDs.nextFaceID()
        let surfaceID = topologyIDs.nextSurfaceID()
        var builtLoops: [BuiltTrimLoop] = []

        model.geometry.surfaces[surfaceID] = surfaceGeometry
        builtLoops.append(try buildTrimLoop(
            parameterDomain,
            surface: surface,
            model: &model,
            topologyIDs: &topologyIDs,
            context: context
        ))
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: builtLoops.map(\.loopID))
        model.shells[shellID] = Shell(id: shellID, faceIDs: [faceID])
        model.bodies[bodyID] = Body(
            id: bodyID,
            sheetShellIDs: [shellID],
            name: feature.name,
            material: surfaceFeature.material
        )
        try model.validate(tolerance: context.tolerance)
        let subshapes = generatedSubshapes(
            featureID: feature.id,
            bodyID: bodyID,
            faceID: faceID,
            builtLoops: builtLoops
        )

        return EvaluationResult(
            brep: model,
            subshapes: subshapes,
            lineage: try GeneratedTopologyLineageBuilder().build(
                featureID: feature.id,
                subshapes: subshapes
            )
        )
    }

    private func buildTrimLoop(
        _ domain: SurfaceParameterDomain2D,
        surface: BSplineSurface3D,
        model: inout BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator,
        context: EvaluationContext
    ) throws -> BuiltTrimLoop {
        let boundaryEdges = rectangularBoundaryEdges(domain: domain)
        let loopID = topologyIDs.nextLoopID()
        var vertexIDs: [VertexID] = []
        var edgeIDs: [EdgeID] = []
        var orientedEdges: [Coedge] = []
        vertexIDs.reserveCapacity(boundaryEdges.count)
        edgeIDs.reserveCapacity(boundaryEdges.count)
        orientedEdges.reserveCapacity(boundaryEdges.count)

        for edge in boundaryEdges {
            let parameter = try edge.parameterCurve.startParameter(tolerance: context.tolerance)
            let vertexID = topologyIDs.nextVertexID()
            model.vertices[vertexID] = Vertex(
                id: vertexID,
                point: try surface.point(u: parameter.u, v: parameter.v, tolerance: context.tolerance)
            )
            vertexIDs.append(vertexID)
        }

        for index in boundaryEdges.indices {
            let boundaryEdge = boundaryEdges[index]
            let nextIndex = (index + 1) % boundaryEdges.count
            let edgeID = try addTrimEdge(
                boundaryEdge.parameterCurve,
                surface: surface,
                startVertexID: vertexIDs[index],
                endVertexID: vertexIDs[nextIndex],
                model: &model,
                topologyIDs: &topologyIDs,
                context: context
            )
            edgeIDs.append(edgeID)
            orientedEdges.append(Coedge(
                edgeID: edgeID,
                orientation: .forward,
                surfaceParameterCurve: boundaryEdge.parameterCurve
            ))
        }

        model.loops[loopID] = Loop(id: loopID, role: .outer, edges: orientedEdges)
        return BuiltTrimLoop(
            loopID: loopID,
            edgeIDs: edgeIDs,
            vertexIDs: vertexIDs
        )
    }

    private func rectangularBoundaryEdges(
        domain: SurfaceParameterDomain2D
    ) -> [BoundaryEdge] {
        [
            BoundaryEdge(
                parameterCurve: .constantV(
                    v: domain.vLowerBound,
                    uStart: domain.uLowerBound,
                    uEnd: domain.uUpperBound
                )
            ),
            BoundaryEdge(
                parameterCurve: .constantU(
                    u: domain.uUpperBound,
                    vStart: domain.vLowerBound,
                    vEnd: domain.vUpperBound
                )
            ),
            BoundaryEdge(
                parameterCurve: .constantV(
                    v: domain.vUpperBound,
                    uStart: domain.uUpperBound,
                    uEnd: domain.uLowerBound
                )
            ),
            BoundaryEdge(
                parameterCurve: .constantU(
                    u: domain.uLowerBound,
                    vStart: domain.vUpperBound,
                    vEnd: domain.vLowerBound
                )
            ),
        ]
    }

    private func addTrimEdge(
        _ parameterCurve: SurfaceParameterCurve,
        surface: BSplineSurface3D,
        startVertexID: VertexID,
        endVertexID: VertexID,
        model: inout BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator,
        context: EvaluationContext
    ) throws -> EdgeID {
        let geometry = try boundaryCurveGeometry(
            parameterCurve: parameterCurve,
            surface: surface,
            tolerance: context.tolerance
        )
        try geometry.curve.validate(tolerance: context.tolerance)
        let edgeID = topologyIDs.nextEdgeID()
        let curveID = topologyIDs.nextCurveID()
        model.geometry.curves[curveID] = geometry.curve
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: geometry.trim
        )
        return edgeID
    }

    private func boundaryCurveGeometry(
        parameterCurve: SurfaceParameterCurve,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> BoundaryCurveGeometry {
        switch parameterCurve {
        case let .constantU(u, vStart, vEnd):
            let curve = try surface.vIsoparametricCurve(atU: u, tolerance: tolerance)
            return BoundaryCurveGeometry(
                curve: .bSpline(curve),
                trim: CurveTrim(startParameter: vStart, endParameter: vEnd)
            )
        case let .constantV(v, uStart, uEnd):
            let curve = try surface.uIsoparametricCurve(atV: v, tolerance: tolerance)
            return BoundaryCurveGeometry(
                curve: .bSpline(curve),
                trim: CurveTrim(startParameter: uStart, endParameter: uEnd)
            )
        case .affine,
             .harmonic,
             .polyline,
             .bSpline,
             .sphericalGreatCircle,
             .certifiedImplicit,
             .certifiedAnalyticImplicit,
             .certifiedAnalyticPair,
             .projectedAnalytic:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A B-spline surface source feature only constructs an isoparametric rectangular patch."
            )
        case let .periodicTranslation(base, uShift, vShift):
            guard uShift == 0.0, vShift == 0.0 else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A non-periodic B-spline surface cannot consume a periodic pcurve translation."
                )
            }
            return try boundaryCurveGeometry(
                parameterCurve: base,
                surface: surface,
                tolerance: tolerance
            )
        }
    }

    private func generatedSubshapes(
        featureID: FeatureID,
        bodyID: BodyID,
        faceID: FaceID,
        builtLoops: [BuiltTrimLoop]
    ) -> [SubshapeID: TopologyReference] {
        var subshapes: [SubshapeID: TopologyReference] = [
            SubshapeID(featureID: featureID, role: GeneratedSubshapeRole.body.rawValue, ordinal: 0): .body(bodyID),
            bSplineSurfaceSubshape(featureID: featureID, role: "patch:0:face"): .face(faceID),
        ]
        for loop in builtLoops {
            for edgeIndex in loop.edgeIDs.indices {
                let edgeName = edgeSubshape(edgeIndex: edgeIndex)
                subshapes[bSplineSurfaceSubshape(featureID: featureID, role: edgeName)] = .edge(loop.edgeIDs[edgeIndex])
                let vertexName = vertexSubshape(vertexIndex: edgeIndex)
                subshapes[bSplineSurfaceSubshape(featureID: featureID, role: vertexName)] = .vertex(loop.vertexIDs[edgeIndex])
            }
        }
        return subshapes
    }

    private func edgeSubshape(edgeIndex: Int) -> String {
        let roles = ["vMin", "uMax", "vMax", "uMin"]
        guard roles.indices.contains(edgeIndex) else {
            return "patch:0:edge:\(edgeIndex)"
        }
        return "patch:0:edge:\(roles[edgeIndex])"
    }

    private func vertexSubshape(vertexIndex: Int) -> String {
        switch vertexIndex {
        case 0:
            return "patch:0:vertex:uMin:vMin"
        case 1:
            return "patch:0:vertex:uMax:vMin"
        case 2:
            return "patch:0:vertex:uMax:vMax"
        case 3:
            return "patch:0:vertex:uMin:vMax"
        default:
            return "patch:0:vertex:\(vertexIndex)"
        }
    }

    private func bSplineSurfaceSubshape(featureID: FeatureID, role: String) -> SubshapeID {
        SubshapeID(
            featureID: featureID,
            role: SubshapeIdentityRole.compose(generatedRole: "bSplineSurface", subshapeRole: role),
            ordinal: 0
        )
    }
}

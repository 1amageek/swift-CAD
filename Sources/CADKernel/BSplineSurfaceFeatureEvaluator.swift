import CADCore
import CADIR

public struct BSplineSurfaceFeatureEvaluator: FeatureEvaluating {
    public init() {}

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .bSplineSurface(surfaceFeature) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation(
                "B-spline surface evaluator requires a B-spline surface feature."
            )
        }
        guard feature.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("B-spline surface source features must not declare inputs.")
        }
        try surfaceFeature.validate(tolerance: context.tolerance)
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
        let trimDomain = try surfaceFeature.resolvedOuterTrimDomain(tolerance: context.tolerance)
        let uBounds = (lower: trimDomain.uLowerBound, upper: trimDomain.uUpperBound)
        let vBounds = (lower: trimDomain.vLowerBound, upper: trimDomain.vUpperBound)
        let bodyID = BodyID()
        let shellID = ShellID()
        let faceID = FaceID()
        let loopID = LoopID()
        let surfaceID = SurfaceID()
        let bottomLeftVertexID = VertexID()
        let bottomRightVertexID = VertexID()
        let topRightVertexID = VertexID()
        let topLeftVertexID = VertexID()

        model.geometry.surfaces[surfaceID] = surfaceGeometry
        model.vertices[bottomLeftVertexID] = Vertex(
            id: bottomLeftVertexID,
            point: try surface.point(u: uBounds.lower, v: vBounds.lower, tolerance: context.tolerance)
        )
        model.vertices[bottomRightVertexID] = Vertex(
            id: bottomRightVertexID,
            point: try surface.point(u: uBounds.upper, v: vBounds.lower, tolerance: context.tolerance)
        )
        model.vertices[topRightVertexID] = Vertex(
            id: topRightVertexID,
            point: try surface.point(u: uBounds.upper, v: vBounds.upper, tolerance: context.tolerance)
        )
        model.vertices[topLeftVertexID] = Vertex(
            id: topLeftVertexID,
            point: try surface.point(u: uBounds.lower, v: vBounds.upper, tolerance: context.tolerance)
        )

        let vMinEdge = try addBoundaryEdge(
            curve: surface.uIsoparametricCurve(atV: vBounds.lower, tolerance: context.tolerance),
            trimBounds: uBounds,
            startVertexID: bottomLeftVertexID,
            endVertexID: bottomRightVertexID,
            model: &model
        )
        let uMaxEdge = try addBoundaryEdge(
            curve: surface.vIsoparametricCurve(atU: uBounds.upper, tolerance: context.tolerance),
            trimBounds: vBounds,
            startVertexID: bottomRightVertexID,
            endVertexID: topRightVertexID,
            model: &model
        )
        let vMaxEdge = try addBoundaryEdge(
            curve: surface.uIsoparametricCurve(atV: vBounds.upper, tolerance: context.tolerance),
            trimBounds: uBounds,
            startVertexID: topLeftVertexID,
            endVertexID: topRightVertexID,
            model: &model
        )
        let uMinEdge = try addBoundaryEdge(
            curve: surface.vIsoparametricCurve(atU: uBounds.lower, tolerance: context.tolerance),
            trimBounds: vBounds,
            startVertexID: bottomLeftVertexID,
            endVertexID: topLeftVertexID,
            model: &model
        )

        model.loops[loopID] = Loop(
            id: loopID,
            role: .outer,
            edges: [
                OrientedEdge(
                    edgeID: vMinEdge.edgeID,
                    orientation: .forward,
                    surfaceParameterCurve: .constantV(v: vBounds.lower, uStart: uBounds.lower, uEnd: uBounds.upper)
                ),
                OrientedEdge(
                    edgeID: uMaxEdge.edgeID,
                    orientation: .forward,
                    surfaceParameterCurve: .constantU(u: uBounds.upper, vStart: vBounds.lower, vEnd: vBounds.upper)
                ),
                OrientedEdge(
                    edgeID: vMaxEdge.edgeID,
                    orientation: .reversed,
                    surfaceParameterCurve: .constantV(v: vBounds.upper, uStart: uBounds.upper, uEnd: uBounds.lower)
                ),
                OrientedEdge(
                    edgeID: uMinEdge.edgeID,
                    orientation: .reversed,
                    surfaceParameterCurve: .constantU(u: uBounds.lower, vStart: vBounds.upper, vEnd: vBounds.lower)
                ),
            ]
        )
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
        model.shells[shellID] = Shell(id: shellID, faceIDs: [faceID])
        model.bodies[bodyID] = Body(
            id: bodyID,
            shellIDs: [shellID],
            kind: .sheet,
            name: feature.name,
            material: surfaceFeature.material
        )
        try model.validate(tolerance: context.tolerance)

        return EvaluationResult(
            brep: model,
            generatedNames: generatedNames(
                featureID: feature.id,
                bodyID: bodyID,
                faceID: faceID,
                vMinEdgeID: vMinEdge.edgeID,
                uMaxEdgeID: uMaxEdge.edgeID,
                vMaxEdgeID: vMaxEdge.edgeID,
                uMinEdgeID: uMinEdge.edgeID,
                bottomLeftVertexID: bottomLeftVertexID,
                bottomRightVertexID: bottomRightVertexID,
                topRightVertexID: topRightVertexID,
                topLeftVertexID: topLeftVertexID
            )
        )
    }

    private func addBoundaryEdge(
        curve: BSplineCurve3D,
        trimBounds: (lower: Double, upper: Double),
        startVertexID: VertexID,
        endVertexID: VertexID,
        model: inout BRepModel
    ) throws -> (edgeID: EdgeID, curveID: CurveID) {
        try curve.validate()
        let edgeID = EdgeID()
        let curveID = CurveID()
        guard try curve.domain.containsSpan(from: trimBounds.lower, to: trimBounds.upper) else {
            throw FeatureEvaluationError.invalidGraph("B-spline surface trim edge must be contained in its curve domain.")
        }
        model.geometry.curves[curveID] = .bSpline(curve)
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: CurveTrim(startParameter: trimBounds.lower, endParameter: trimBounds.upper)
        )
        return (edgeID, curveID)
    }

    private func generatedNames(
        featureID: FeatureID,
        bodyID: BodyID,
        faceID: FaceID,
        vMinEdgeID: EdgeID,
        uMaxEdgeID: EdgeID,
        vMaxEdgeID: EdgeID,
        uMinEdgeID: EdgeID,
        bottomLeftVertexID: VertexID,
        bottomRightVertexID: VertexID,
        topRightVertexID: VertexID,
        topLeftVertexID: VertexID
    ) -> [PersistentName: TopologyReference] {
        [
            bSplineSurfaceName(featureID: featureID, subshape: "body"): .body(bodyID),
            bSplineSurfaceName(featureID: featureID, subshape: "patch:0:face"): .face(faceID),
            bSplineSurfaceName(featureID: featureID, subshape: "patch:0:edge:vMin"): .edge(vMinEdgeID),
            bSplineSurfaceName(featureID: featureID, subshape: "patch:0:edge:uMax"): .edge(uMaxEdgeID),
            bSplineSurfaceName(featureID: featureID, subshape: "patch:0:edge:vMax"): .edge(vMaxEdgeID),
            bSplineSurfaceName(featureID: featureID, subshape: "patch:0:edge:uMin"): .edge(uMinEdgeID),
            bSplineSurfaceName(featureID: featureID, subshape: "patch:0:vertex:uMin:vMin"): .vertex(bottomLeftVertexID),
            bSplineSurfaceName(featureID: featureID, subshape: "patch:0:vertex:uMax:vMin"): .vertex(bottomRightVertexID),
            bSplineSurfaceName(featureID: featureID, subshape: "patch:0:vertex:uMax:vMax"): .vertex(topRightVertexID),
            bSplineSurfaceName(featureID: featureID, subshape: "patch:0:vertex:uMin:vMax"): .vertex(topLeftVertexID),
        ]
    }

    private func bSplineSurfaceName(featureID: FeatureID, subshape: String) -> PersistentName {
        PersistentName(components: [
            .feature(featureID),
            .generated("bSplineSurface"),
            .subshape(subshape),
        ])
    }
}

import CADCore
import CADIR

public struct BSplineSurfaceFeatureEvaluator: FeatureEvaluating {
    private struct BuiltTrimLoop {
        var loopID: LoopID
        var role: LoopRole
        var orientedEdges: [OrientedEdge]
        var edgeIDs: [EdgeID]
        var vertexIDs: [VertexID]
        var sourceLoop: BSplineSurfaceTrimLoop
    }

    private struct TrimCurveApproximation {
        var curve: BSplineCurve3D
        var trim: CurveTrim
        var maximumDeviation: Double?
    }

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
        let trimLoops = try surfaceFeature.resolvedTrimLoops(tolerance: context.tolerance)
        let bodyID = BodyID()
        let shellID = ShellID()
        let faceID = FaceID()
        let surfaceID = SurfaceID()
        var builtLoops: [BuiltTrimLoop] = []

        model.geometry.surfaces[surfaceID] = surfaceGeometry
        for trimLoop in trimLoops {
            builtLoops.append(try buildTrimLoop(
                trimLoop,
                surface: surface,
                model: &model,
                context: context
            ))
        }
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: builtLoops.map(\.loopID))
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
                builtLoops: builtLoops
            )
        )
    }

    private func buildTrimLoop(
        _ trimLoop: BSplineSurfaceTrimLoop,
        surface: BSplineSurface3D,
        model: inout BRepModel,
        context: EvaluationContext
    ) throws -> BuiltTrimLoop {
        let loopID = LoopID()
        var vertexIDs: [VertexID] = []
        var edgeIDs: [EdgeID] = []
        var orientedEdges: [OrientedEdge] = []
        vertexIDs.reserveCapacity(trimLoop.edges.count)
        edgeIDs.reserveCapacity(trimLoop.edges.count)
        orientedEdges.reserveCapacity(trimLoop.edges.count)

        for edge in trimLoop.edges {
            let parameter = try edge.startParameter(tolerance: context.tolerance)
            let vertexID = VertexID()
            model.vertices[vertexID] = Vertex(
                id: vertexID,
                point: try surface.point(u: parameter.u, v: parameter.v, tolerance: context.tolerance)
            )
            vertexIDs.append(vertexID)
        }

        for index in trimLoop.edges.indices {
            let trimEdge = trimLoop.edges[index]
            let nextIndex = (index + 1) % trimLoop.edges.count
            let edgeID = try addTrimEdge(
                trimEdge,
                surface: surface,
                startVertexID: vertexIDs[index],
                endVertexID: vertexIDs[nextIndex],
                model: &model,
                context: context
            )
            edgeIDs.append(edgeID)
            orientedEdges.append(OrientedEdge(
                edgeID: edgeID,
                orientation: .forward,
                surfaceParameterCurve: trimEdge.parameterCurve
            ))
        }

        model.loops[loopID] = Loop(id: loopID, role: trimLoop.role, edges: orientedEdges)
        return BuiltTrimLoop(
            loopID: loopID,
            role: trimLoop.role,
            orientedEdges: orientedEdges,
            edgeIDs: edgeIDs,
            vertexIDs: vertexIDs,
            sourceLoop: trimLoop
        )
    }

    private func addTrimEdge(
        _ trimEdge: BSplineSurfaceTrimEdge,
        surface: BSplineSurface3D,
        startVertexID: VertexID,
        endVertexID: VertexID,
        model: inout BRepModel,
        context: EvaluationContext
    ) throws -> EdgeID {
        let approximation = try trimCurveApproximation(
            parameterCurve: trimEdge.parameterCurve,
            surface: surface,
            tolerance: context.tolerance
        )
        try approximation.curve.validate(tolerance: context.tolerance)
        let edgeID = EdgeID()
        let curveID = CurveID()
        model.geometry.curves[curveID] = .bSpline(approximation.curve)
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: approximation.trim,
            surfaceApproximationTolerance: approximation.maximumDeviation
        )
        return edgeID
    }

    private func trimCurveApproximation(
        parameterCurve: SurfaceParameterCurve,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> TrimCurveApproximation {
        switch parameterCurve {
        case let .constantU(u, vStart, vEnd):
            let curve = try surface.vIsoparametricCurve(atU: u, tolerance: tolerance)
            return TrimCurveApproximation(
                curve: curve,
                trim: CurveTrim(startParameter: vStart, endParameter: vEnd),
                maximumDeviation: nil
            )
        case let .constantV(v, uStart, uEnd):
            let curve = try surface.uIsoparametricCurve(atV: v, tolerance: tolerance)
            return TrimCurveApproximation(
                curve: curve,
                trim: CurveTrim(startParameter: uStart, endParameter: uEnd),
                maximumDeviation: nil
            )
        case .polyline, .bSpline:
            return try approximateTrimCurve(
                parameterCurve: parameterCurve,
                surface: surface,
                tolerance: tolerance
            )
        }
    }

    private func approximateTrimCurve(
        parameterCurve: SurfaceParameterCurve,
        surface: BSplineSurface3D,
        tolerance: ModelingTolerance
    ) throws -> TrimCurveApproximation {
        var segmentCount = 16
        var sampledPoints: [Point3D] = []
        var maximumDeviation = Double.greatestFiniteMagnitude
        while segmentCount <= 1024 {
            sampledPoints = try sampledSurfacePoints(
                parameterCurve: parameterCurve,
                surface: surface,
                segmentCount: segmentCount,
                tolerance: tolerance
            )
            maximumDeviation = try maximumChordDeviation(
                parameterCurve: parameterCurve,
                surface: surface,
                sampledPoints: sampledPoints,
                tolerance: tolerance
            )
            if maximumDeviation <= tolerance.distance {
                break
            }
            segmentCount *= 2
        }
        guard sampledPoints.count >= 2,
              maximumDeviation.isFinite else {
            throw FeatureEvaluationError.invalidGraph("B-spline surface trim curve approximation failed.")
        }
        let curve = BSplineCurve3D(
            degree: 1,
            knots: openUniformDegreeOneKnots(controlPointCount: sampledPoints.count),
            controlPoints: sampledPoints
        )
        try curve.validate(tolerance: tolerance)
        return TrimCurveApproximation(
            curve: curve,
            trim: CurveTrim(startParameter: 0.0, endParameter: Double(sampledPoints.count - 1)),
            maximumDeviation: maximumDeviation
        )
    }

    private func sampledSurfacePoints(
        parameterCurve: SurfaceParameterCurve,
        surface: BSplineSurface3D,
        segmentCount: Int,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        try (0...segmentCount).map { index in
            let fraction = Double(index) / Double(segmentCount)
            let parameter = try parameterCurve.parameter(atNormalizedFraction: fraction, tolerance: tolerance)
            return try surface.point(u: parameter.u, v: parameter.v, tolerance: tolerance)
        }
    }

    private func maximumChordDeviation(
        parameterCurve: SurfaceParameterCurve,
        surface: BSplineSurface3D,
        sampledPoints: [Point3D],
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard sampledPoints.count >= 2 else {
            throw FeatureEvaluationError.invalidGraph("B-spline surface trim approximation requires at least two samples.")
        }
        let segmentCount = sampledPoints.count - 1
        var maximumDeviation = 0.0
        for segmentIndex in 0..<segmentCount {
            for localFraction in [0.25, 0.5, 0.75] {
                let globalFraction = (Double(segmentIndex) + localFraction) / Double(segmentCount)
                let parameter = try parameterCurve.parameter(
                    atNormalizedFraction: globalFraction,
                    tolerance: tolerance
                )
                let surfacePoint = try surface.point(u: parameter.u, v: parameter.v, tolerance: tolerance)
                let chordPoint = interpolated(
                    sampledPoints[segmentIndex],
                    sampledPoints[segmentIndex + 1],
                    fraction: localFraction
                )
                maximumDeviation = max(maximumDeviation, (surfacePoint - chordPoint).length)
            }
        }
        return maximumDeviation
    }

    private func openUniformDegreeOneKnots(controlPointCount: Int) -> [Double] {
        guard controlPointCount >= 2 else {
            return [0.0, 0.0, 0.0, 0.0]
        }
        if controlPointCount == 2 {
            return [0.0, 0.0, 1.0, 1.0]
        }
        return [0.0, 0.0]
            + (1..<(controlPointCount - 1)).map(Double.init)
            + [Double(controlPointCount - 1), Double(controlPointCount - 1)]
    }

    private func interpolated(_ start: Point3D, _ end: Point3D, fraction: Double) -> Point3D {
        Point3D(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction,
            z: start.z + (end.z - start.z) * fraction
        )
    }

    private func generatedNames(
        featureID: FeatureID,
        bodyID: BodyID,
        faceID: FaceID,
        builtLoops: [BuiltTrimLoop]
    ) -> [PersistentName: TopologyReference] {
        var names: [PersistentName: TopologyReference] = [
            bSplineSurfaceName(featureID: featureID, subshape: "body"): .body(bodyID),
            bSplineSurfaceName(featureID: featureID, subshape: "patch:0:face"): .face(faceID),
        ]
        for loopIndex in builtLoops.indices {
            let loop = builtLoops[loopIndex]
            for edgeIndex in loop.edgeIDs.indices {
                let edgeName = edgeSubshape(loop: loop, loopIndex: loopIndex, edgeIndex: edgeIndex)
                names[bSplineSurfaceName(featureID: featureID, subshape: edgeName)] = .edge(loop.edgeIDs[edgeIndex])
                let vertexName = vertexSubshape(loop: loop, loopIndex: loopIndex, vertexIndex: edgeIndex)
                names[bSplineSurfaceName(featureID: featureID, subshape: vertexName)] = .vertex(loop.vertexIDs[edgeIndex])
            }
        }
        return names
    }

    private func edgeSubshape(
        loop: BuiltTrimLoop,
        loopIndex: Int,
        edgeIndex: Int
    ) -> String {
        if loopIndex == 0,
           let role = loop.sourceLoop.edges[edgeIndex].role,
           loop.sourceLoop.isRectangularBoundaryLoop {
            return "patch:0:edge:\(role)"
        }
        return "patch:0:loop:\(loopIndex):edge:\(edgeIndex)"
    }

    private func vertexSubshape(
        loop: BuiltTrimLoop,
        loopIndex: Int,
        vertexIndex: Int
    ) -> String {
        if loopIndex == 0,
           loop.sourceLoop.isRectangularBoundaryLoop {
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
                break
            }
        }
        return "patch:0:loop:\(loopIndex):vertex:\(vertexIndex)"
    }

    private func bSplineSurfaceName(featureID: FeatureID, subshape: String) -> PersistentName {
        PersistentName(components: [
            .feature(featureID),
            .generated("bSplineSurface"),
            .subshape(subshape),
        ])
    }
}

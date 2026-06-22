import CADCore
import CADIR

public struct PolySplineFeatureEvaluator: Sendable {
    public init() {}

    public func evaluate(feature: FeatureNode, context: EvaluationContext) throws -> EvaluationResult {
        guard case let .polySpline(polySpline) = feature.operation else {
            throw FeatureEvaluationError.unsupportedOperation("PolySpline evaluator requires a PolySpline feature.")
        }
        guard feature.inputs.isEmpty else {
            throw FeatureEvaluationError.invalidGraph("PolySpline inline mesh subset must not declare inputs.")
        }
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: polySpline.sourceMesh,
            options: polySpline.options,
            tolerance: context.tolerance
        )
        guard analysis.result.isSupported,
              !analysis.supportedPatches.isEmpty else {
            throw FeatureEvaluationError.unsupportedOperation(
                "PolySpline source mesh is not supported: \(analysis.result.failureMessage ?? "No supported patch candidate.")"
            )
        }
        return try buildSheetBody(
            patches: analysis.supportedPatches,
            feature: feature,
            sourceMesh: polySpline.sourceMesh,
            context: context
        )
    }

    private func buildSheetBody(
        patches: [PolySplineMeshAnalyzer.Analysis.SupportedPatch],
        feature: FeatureNode,
        sourceMesh: Mesh,
        context: EvaluationContext
    ) throws -> EvaluationResult {
        var model = context.brep
        let bodyID = BodyID()
        let shellID = ShellID()
        var generatedNames: [PersistentName: TopologyReference] = [
            polySplineName(featureID: feature.id, subshape: "body"): .body(bodyID),
        ]
        var vertexIDsBySourceIndex: [Int: VertexID] = [:]
        var edgeRecordsByVertexPair: [PolySplinePatchGraph.VertexPair: PolySplineEdgeRecord] = [:]
        var faceIDs: [FaceID] = []

        for patch in patches.sorted(by: { $0.candidateID < $1.candidateID }) {
            guard patch.boundaryVertexIndices.count == 4,
                  patch.boundaryPoints.count == 4 else {
                throw FeatureEvaluationError.invalidGraph("PolySpline supported patches must be quad patches.")
            }
            let surface = BSplineSurface3D.cubicBezierPatch(
                bottomLeft: patch.boundaryPoints[0],
                bottomRight: patch.boundaryPoints[1],
                topRight: patch.boundaryPoints[2],
                topLeft: patch.boundaryPoints[3]
            )
            try surface.validate(tolerance: context.tolerance)
            let faceID = FaceID()
            let loopID = LoopID()
            let surfaceID = SurfaceID()
            model.geometry.surfaces[surfaceID] = .bSpline(surface)
            let vertexIDs = try localVertexIDs(
                for: patch,
                sourceMesh: sourceMesh,
                vertexIDsBySourceIndex: &vertexIDsBySourceIndex,
                model: &model,
                tolerance: context.tolerance
            )
            let orientedEdges = try localOrientedEdges(
                for: patch,
                vertexIDs: vertexIDs,
                edgeRecordsByVertexPair: &edgeRecordsByVertexPair,
                model: &model,
                tolerance: context.tolerance
            )
            model.loops[loopID] = Loop(id: loopID, role: .outer, edges: orientedEdges)
            model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
            faceIDs.append(faceID)
            generatedNames.merge(
                generatedPatchNames(
                    featureID: feature.id,
                    patchID: patch.candidateID,
                    faceID: faceID,
                    orientedEdges: orientedEdges,
                    vertexIDs: vertexIDs
                ),
                uniquingKeysWith: { current, _ in current }
            )
        }
        model.shells[shellID] = Shell(id: shellID, faceIDs: faceIDs)
        model.bodies[bodyID] = Body(
            id: bodyID,
            shellIDs: [shellID],
            kind: .sheet,
            name: feature.name,
            material: sourceMesh.material
        )
        try model.validate(tolerance: context.tolerance)

        return EvaluationResult(
            brep: model,
            generatedNames: generatedNames
        )
    }

    private func localVertexIDs(
        for patch: PolySplineMeshAnalyzer.Analysis.SupportedPatch,
        sourceMesh: Mesh,
        vertexIDsBySourceIndex: inout [Int: VertexID],
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [VertexID] {
        var vertexIDs: [VertexID] = []
        vertexIDs.reserveCapacity(patch.boundaryVertexIndices.count)
        for (index, sourceVertexIndex) in patch.boundaryVertexIndices.enumerated() {
            guard sourceMesh.positions.indices.contains(sourceVertexIndex) else {
                throw FeatureEvaluationError.invalidGraph("PolySpline patch references a missing source vertex.")
            }
            let point = sourceMesh.positions[sourceVertexIndex]
            if let vertexID = vertexIDsBySourceIndex[sourceVertexIndex] {
                guard let storedPoint = model.vertices[vertexID]?.point,
                      storedPoint.isApproximatelyEqual(to: point, tolerance: tolerance.distance) else {
                    throw FeatureEvaluationError.invalidGraph("PolySpline shared source vertex has inconsistent points.")
                }
                vertexIDs.append(vertexID)
            } else {
                let vertexID = VertexID()
                model.vertices[vertexID] = Vertex(id: vertexID, point: patch.boundaryPoints[index])
                vertexIDsBySourceIndex[sourceVertexIndex] = vertexID
                vertexIDs.append(vertexID)
            }
        }
        return vertexIDs
    }

    private func localOrientedEdges(
        for patch: PolySplineMeshAnalyzer.Analysis.SupportedPatch,
        vertexIDs: [VertexID],
        edgeRecordsByVertexPair: inout [PolySplinePatchGraph.VertexPair: PolySplineEdgeRecord],
        model: inout BRepModel,
        tolerance: ModelingTolerance
    ) throws -> [OrientedEdge] {
        var orientedEdges: [OrientedEdge] = []
        orientedEdges.reserveCapacity(vertexIDs.count)
        for index in vertexIDs.indices {
            let nextIndex = (index + 1) % vertexIDs.count
            let sourceStart = patch.boundaryVertexIndices[index]
            let sourceEnd = patch.boundaryVertexIndices[nextIndex]
            let vertexPair = PolySplinePatchGraph.VertexPair(
                firstVertexIndex: sourceStart,
                secondVertexIndex: sourceEnd
            )
            if let record = edgeRecordsByVertexPair[vertexPair] {
                let orientation: Orientation
                if record.startVertexID == vertexIDs[index],
                   record.endVertexID == vertexIDs[nextIndex] {
                    orientation = .forward
                } else if record.startVertexID == vertexIDs[nextIndex],
                          record.endVertexID == vertexIDs[index] {
                    orientation = .reversed
                } else {
                    throw FeatureEvaluationError.invalidGraph("PolySpline shared edge has inconsistent vertices.")
                }
                orientedEdges.append(OrientedEdge(edgeID: record.edgeID, orientation: orientation))
            } else {
                let edgeID = EdgeID()
                let curveID = CurveID()
                let startPoint = patch.boundaryPoints[index]
                let endPoint = patch.boundaryPoints[nextIndex]
                let direction = try (endPoint - startPoint).normalized(tolerance: tolerance.distance)
                model.geometry.curves[curveID] = .line(Line3D(origin: startPoint, direction: direction))
                model.edges[edgeID] = Edge(
                    id: edgeID,
                    curveID: curveID,
                    startVertexID: vertexIDs[index],
                    endVertexID: vertexIDs[nextIndex]
                )
                edgeRecordsByVertexPair[vertexPair] = PolySplineEdgeRecord(
                    edgeID: edgeID,
                    startVertexID: vertexIDs[index],
                    endVertexID: vertexIDs[nextIndex]
                )
                orientedEdges.append(OrientedEdge(edgeID: edgeID, orientation: .forward))
            }
        }
        return orientedEdges
    }

    private func generatedPatchNames(
        featureID: FeatureID,
        patchID: Int,
        faceID: FaceID,
        orientedEdges: [OrientedEdge],
        vertexIDs: [VertexID]
    ) -> [PersistentName: TopologyReference] {
        var names: [PersistentName: TopologyReference] = [
            polySplineName(featureID: featureID, subshape: "patch:\(patchID):face"): .face(faceID),
        ]
        let edgeRoles = ["edge:vMin", "edge:uMax", "edge:vMax", "edge:uMin"]
        for (index, orientedEdge) in orientedEdges.enumerated() {
            names[
                polySplineName(
                    featureID: featureID,
                    subshape: "patch:\(patchID):\(edgeRoles[index])"
                )
            ] = .edge(orientedEdge.edgeID)
        }
        let vertexRoles = [
            "vertex:uMin:vMin",
            "vertex:uMax:vMin",
            "vertex:uMax:vMax",
            "vertex:uMin:vMax",
        ]
        for (index, vertexID) in vertexIDs.enumerated() {
            names[
                polySplineName(
                    featureID: featureID,
                    subshape: "patch:\(patchID):\(vertexRoles[index])"
                )
            ] = .vertex(vertexID)
        }
        return names
    }

    private func polySplineName(featureID: FeatureID, subshape: String) -> PersistentName {
        PersistentName(components: [
            .feature(featureID),
            .generated("polySpline"),
            .subshape(subshape),
        ])
    }
}

private struct PolySplineEdgeRecord {
    var edgeID: EdgeID
    var startVertexID: VertexID
    var endVertexID: VertexID
}

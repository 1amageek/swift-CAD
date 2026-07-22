import CADCore
import CADIR
import CADModeling
import CADTopology

struct SourceBRepFacePatchBuilder {
    struct Result {
        let patch: BRepSewingFacePatch
        let stableKeys: [TopologyReference: BRepSewingStableKey]
    }

    func build(
        faceID: FaceID,
        stableID: String,
        from model: BRepModel,
        sourceSubshapes: [SubshapeID: TopologyReference],
        tolerance: ModelingTolerance
    ) throws -> Result {
        try tolerance.validate()
        guard stableID.isEmpty == false,
              let face = model.faces[faceID],
              let surface = model.geometry.surfaces[face.surfaceID] else {
            throw missingReference(
                "Source face-patch extraction references missing face geometry.",
                tolerance: tolerance
            )
        }
        var stableKeys: [TopologyReference: BRepSewingStableKey] = [
            .face(faceID): .face(stableID),
        ]
        var sewingLoops: [BRepSewingLoop] = []
        for (loopIndex, loopID) in face.loops.enumerated() {
            guard let loop = model.loops[loopID] else {
                throw missingReference(
                    "Source face-patch extraction references a missing loop.",
                    tolerance: tolerance
                )
            }
            let loopStableID = "\(stableID):loop:\(loopIndex)"
            var sewingEdges: [BRepSewingEdge] = []
            for (useIndex, coedge) in loop.edges.enumerated() {
                guard let edge = model.edges[coedge.edgeID],
                      let curve = model.geometry.curves[edge.curveID],
                      let storedStart = model.vertices[edge.startVertexID]?.point,
                      let storedEnd = model.vertices[edge.endVertexID]?.point,
                      let trim = edge.trim,
                      let pcurve = coedge.surfaceParameterCurve else {
                    throw missingReference(
                        "Exact source face-patch extraction requires edge geometry, vertices, and a face-local pcurve.",
                        tolerance: tolerance
                    )
                }
                let edgeStableID = "\(loopStableID):edge-use:\(useIndex)"
                let oriented = orientedEdge(
                    edge: edge,
                    trim: trim,
                    storedStart: storedStart,
                    storedEnd: storedEnd,
                    orientation: coedge.orientation
                )
                sewingEdges.append(BRepSewingEdge(
                    stableID: edgeStableID,
                    curve: curve,
                    startParameter: oriented.startParameter,
                    endParameter: oriented.endParameter,
                    startPoint: oriented.startPoint,
                    endPoint: oriented.endPoint,
                    surfaceParameterCurve: pcurve,
                    parentSubshapeIDs: sourceSubshapeIDs(
                        for: .edge(edge.id),
                        in: sourceSubshapes
                    ),
                    startVertexParentSubshapeIDs: sourceSubshapeIDs(
                        for: .vertex(oriented.startVertexID),
                        in: sourceSubshapes
                    ),
                    endVertexParentSubshapeIDs: sourceSubshapeIDs(
                        for: .vertex(oriented.endVertexID),
                        in: sourceSubshapes
                    )
                ))
                if stableKeys[.edge(edge.id)] == nil {
                    stableKeys[.edge(edge.id)] = .edge(edgeStableID)
                }
                if stableKeys[.vertex(oriented.startVertexID)] == nil {
                    stableKeys[.vertex(oriented.startVertexID)] = .startVertex(edge: edgeStableID)
                }
                if stableKeys[.vertex(oriented.endVertexID)] == nil {
                    stableKeys[.vertex(oriented.endVertexID)] = .endVertex(edge: edgeStableID)
                }
            }
            sewingLoops.append(BRepSewingLoop(
                stableID: loopStableID,
                role: loop.role,
                edges: sewingEdges
            ))
        }
        return Result(
            patch: BRepSewingFacePatch(
                stableID: stableID,
                surface: surface,
                orientation: face.orientation,
                loops: sewingLoops,
                parentSubshapeIDs: sourceSubshapeIDs(
                    for: .face(faceID),
                    in: sourceSubshapes
                )
            ),
            stableKeys: stableKeys
        )
    }

    private func orientedEdge(
        edge: Edge,
        trim: CurveTrim,
        storedStart: Point3D,
        storedEnd: Point3D,
        orientation: Orientation
    ) -> OrientedEdge {
        switch orientation {
        case .forward:
            return OrientedEdge(
                startParameter: trim.startParameter,
                endParameter: trim.endParameter,
                startPoint: storedStart,
                endPoint: storedEnd,
                startVertexID: edge.startVertexID,
                endVertexID: edge.endVertexID
            )
        case .reversed:
            return OrientedEdge(
                startParameter: trim.endParameter,
                endParameter: trim.startParameter,
                startPoint: storedEnd,
                endPoint: storedStart,
                startVertexID: edge.endVertexID,
                endVertexID: edge.startVertexID
            )
        }
    }

    private func sourceSubshapeIDs(
        for reference: TopologyReference,
        in sourceSubshapes: [SubshapeID: TopologyReference]
    ) -> [SubshapeID] {
        sourceSubshapes.compactMap { subshapeID, candidate in
            candidate == reference ? subshapeID : nil
        }.sorted()
    }

    private func missingReference(
        _ message: String,
        tolerance: ModelingTolerance
    ) -> KernelError {
        KernelError(
            phase: .topology,
            code: .missingReference,
            tolerance: tolerance,
            message: message
        )
    }

    private struct OrientedEdge {
        let startParameter: Double
        let endParameter: Double
        let startPoint: Point3D
        let endPoint: Point3D
        let startVertexID: VertexID
        let endVertexID: VertexID
    }
}

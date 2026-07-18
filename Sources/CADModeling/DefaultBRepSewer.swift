import CADCore
import CADGeometry
import CADIR
import CADTopology

public struct DefaultBRepSewer: BRepSewing {
    public init() {}

    public func sew(
        _ request: BRepSewingRequest,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingResult {
        try request.validate(tolerance: tolerance)
        let result = try sewValidated(request, tolerance: tolerance)
        try result.brep.validate(level: .exact, tolerance: tolerance)
        return result
    }

    package func sewValidated(
        _ request: BRepSewingRequest,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingResult {
        var topologyIDs = FeatureTopologyIDAllocator(featureID: request.featureID)
        var model = BRepModel()
        var allVertices: [VertexRecord] = []
        var allEdges: [EdgeRecord] = []
        var allFaces: [FaceRecord] = []
        var shellIDs: [ShellID] = []
        var stableReferences: [BRepSewingStableKey: TopologyReference] = [:]

        for shell in request.shells.sorted(by: { $0.stableID < $1.stableID }) {
            var vertices: [VertexRecord] = []
            var edges: [EdgeRecord] = []
            var faceRecords: [FaceRecord] = []
            for patch in shell.patches.sorted(by: { $0.stableID < $1.stableID }) {
                let surfaceID = topologyIDs.nextSurfaceID()
                let faceID = topologyIDs.nextFaceID()
                model.geometry.surfaces[surfaceID] = patch.surface
                stableReferences[.face(patch.stableID)] = .face(faceID)
                var loopIDs: [LoopID] = []
                let orderedLoops = patch.loops.sorted {
                    if $0.role != $1.role { return $0.role == .outer }
                    return $0.stableID < $1.stableID
                }
                for loop in orderedLoops {
                    let loopID = topologyIDs.nextLoopID()
                    var coedges: [Coedge] = []
                    for sewingEdge in loop.edges {
                        let startVertexID = canonicalVertex(
                            for: sewingEdge.startPoint,
                            parents: sewingEdge.startVertexParentSubshapeIDs,
                            records: &vertices,
                            model: &model,
                            topologyIDs: &topologyIDs,
                            tolerance: tolerance
                        )
                        let endVertexID = canonicalVertex(
                            for: sewingEdge.endPoint,
                            parents: sewingEdge.endVertexParentSubshapeIDs,
                            records: &vertices,
                            model: &model,
                            topologyIDs: &topologyIDs,
                            tolerance: tolerance
                        )
                        guard startVertexID != endVertexID else {
                            throw KernelError(
                                phase: .topology,
                                code: .topologyFailure,
                                tolerance: tolerance,
                                message: "Sewing collapsed an edge to one canonical vertex."
                            )
                        }
                        let use = try canonicalEdge(
                            sewingEdge,
                            startVertexID: startVertexID,
                            endVertexID: endVertexID,
                            records: &edges,
                            model: &model,
                            topologyIDs: &topologyIDs,
                            tolerance: tolerance
                        )
                        stableReferences[.edge(sewingEdge.stableID)] = .edge(use.edgeID)
                        stableReferences[.startVertex(edge: sewingEdge.stableID)] = .vertex(startVertexID)
                        stableReferences[.endVertex(edge: sewingEdge.stableID)] = .vertex(endVertexID)
                        coedges.append(Coedge(
                            edgeID: use.edgeID,
                            orientation: use.orientation,
                            surfaceParameterCurve: sewingEdge.surfaceParameterCurve
                        ))
                    }
                    model.loops[loopID] = Loop(id: loopID, role: loop.role, coedges: coedges)
                    loopIDs.append(loopID)
                }
                model.faces[faceID] = Face(
                    id: faceID,
                    surfaceID: surfaceID,
                    loops: loopIDs,
                    orientation: patch.orientation
                )
                faceRecords.append(FaceRecord(
                    id: faceID,
                    parents: patch.parentSubshapeIDs
                ))
            }
            try validateEdgeUses(edges, bodyKind: request.bodyKind, tolerance: tolerance)
            let shellID = topologyIDs.nextShellID()
            model.shells[shellID] = Shell(
                id: shellID,
                faceIDs: faceRecords.map(\.id),
                orientation: shell.orientation
            )
            shellIDs.append(shellID)
            allVertices.append(contentsOf: vertices)
            allEdges.append(contentsOf: edges)
            allFaces.append(contentsOf: faceRecords)
        }

        let bodyID = topologyIDs.nextBodyID()
        model.bodies[bodyID] = Body(
            id: bodyID,
            shellIDs: shellIDs,
            kind: request.bodyKind
        )
        stableReferences[.body] = .body(bodyID)
        let identity = topologyIdentity(
            featureID: request.featureID,
            bodyID: bodyID,
            bodyParents: request.bodyParentSubshapeIDs,
            faces: allFaces,
            edges: allEdges,
            vertices: allVertices
        )
        return BRepSewingResult(
            brep: model,
            bodyID: bodyID,
            subshapes: identity.subshapes,
            lineage: identity.lineage,
            stableReferences: stableReferences
        )
    }

    private func canonicalVertex(
        for point: Point3D,
        parents: [SubshapeID],
        records: inout [VertexRecord],
        model: inout BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator,
        tolerance: ModelingTolerance
    ) -> VertexID {
        if let index = records.firstIndex(where: {
            $0.point.isApproximatelyEqual(to: point, tolerance: tolerance.distance)
        }) {
            records[index].parents.formUnion(parents)
            return records[index].id
        }
        let id = topologyIDs.nextVertexID()
        model.vertices[id] = Vertex(id: id, point: point)
        records.append(VertexRecord(id: id, point: point, parents: Set(parents)))
        return id
    }

    private func canonicalEdge(
        _ sewingEdge: BRepSewingEdge,
        startVertexID: VertexID,
        endVertexID: VertexID,
        records: inout [EdgeRecord],
        model: inout BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator,
        tolerance: ModelingTolerance
    ) throws -> EdgeUse {
        let samples = try curveSamples(sewingEdge, tolerance: tolerance)
        for index in records.indices {
            let orientation: Orientation
            let expectedSamples: [Point3D]
            if records[index].startVertexID == startVertexID,
               records[index].endVertexID == endVertexID {
                orientation = .forward
                expectedSamples = records[index].samples
            } else if records[index].startVertexID == endVertexID,
                      records[index].endVertexID == startVertexID {
                orientation = .reversed
                expectedSamples = Array(records[index].samples.reversed())
            } else {
                continue
            }
            guard zip(samples, expectedSamples).allSatisfy({ pair in
                pair.0.isApproximatelyEqual(to: pair.1, tolerance: tolerance.distance)
            }) else {
                continue
            }
            records[index].orientations.append(orientation)
            records[index].parents.formUnion(sewingEdge.parentSubshapeIDs)
            records[index].stableIDs.insert(sewingEdge.stableID)
            return EdgeUse(edgeID: records[index].id, orientation: orientation)
        }

        let curveID = topologyIDs.nextCurveID()
        let edgeID = topologyIDs.nextEdgeID()
        model.geometry.curves[curveID] = sewingEdge.curve
        model.edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: CurveTrim(
                startParameter: sewingEdge.startParameter,
                endParameter: sewingEdge.endParameter
            )
        )
        records.append(EdgeRecord(
            id: edgeID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            samples: samples,
            orientations: [.forward],
            parents: Set(sewingEdge.parentSubshapeIDs),
            stableIDs: [sewingEdge.stableID]
        ))
        return EdgeUse(edgeID: edgeID, orientation: .forward)
    }

    private func curveSamples(
        _ edge: BRepSewingEdge,
        tolerance: ModelingTolerance
    ) throws -> [Point3D] {
        try (0...4).map { index in
            let fraction = Double(index) / 4.0
            let parameter = edge.startParameter
                + (edge.endParameter - edge.startParameter) * fraction
            return try edge.curve.point(at: parameter, tolerance: tolerance)
        }
    }

    private func validateEdgeUses(
        _ edges: [EdgeRecord],
        bodyKind: BodyKind,
        tolerance: ModelingTolerance
    ) throws {
        for edge in edges {
            let forwardCount = edge.orientations.filter { $0 == .forward }.count
            let reversedCount = edge.orientations.filter { $0 == .reversed }.count
            switch bodyKind {
            case .solid:
                guard edge.orientations.count == 2,
                      forwardCount == 1,
                      reversedCount == 1 else {
                    throw KernelError(
                        phase: .topology,
                        code: edge.orientations.count > 2 ? .nonManifoldResult : .topologyFailure,
                        tolerance: tolerance,
                        message: "Solid sewing edge \(edge.stableIDs.sorted()) has \(edge.orientations.count) uses with \(forwardCount) forward and \(reversedCount) reversed."
                    )
                }
            case .sheet:
                guard edge.orientations.count == 1
                    || (edge.orientations.count == 2 && forwardCount == 1 && reversedCount == 1) else {
                    throw KernelError(
                        phase: .topology,
                        code: .nonManifoldResult,
                        tolerance: tolerance,
                        message: "Sheet sewing edge use is non-manifold or inconsistently oriented."
                    )
                }
            }
        }
    }

    private func topologyIdentity(
        featureID: FeatureID,
        bodyID: BodyID,
        bodyParents: [SubshapeID],
        faces: [FaceRecord],
        edges: [EdgeRecord],
        vertices: [VertexRecord]
    ) -> IdentityResult {
        var subshapes: [SubshapeID: TopologyReference] = [:]
        var drafts: [LineageDraft] = []
        let bodySubshape = SubshapeID(featureID: featureID, role: "body", ordinal: 0)
        subshapes[bodySubshape] = .body(bodyID)
        drafts.append(LineageDraft(output: bodySubshape, parents: bodyParents))
        for (ordinal, face) in faces.enumerated() {
            let subshape = SubshapeID(featureID: featureID, role: "face", ordinal: ordinal)
            subshapes[subshape] = .face(face.id)
            drafts.append(LineageDraft(output: subshape, parents: face.parents))
        }
        for (ordinal, edge) in edges.enumerated() {
            let subshape = SubshapeID(featureID: featureID, role: "edge", ordinal: ordinal)
            subshapes[subshape] = .edge(edge.id)
            drafts.append(LineageDraft(output: subshape, parents: Array(edge.parents).sorted()))
        }
        for (ordinal, vertex) in vertices.enumerated() {
            let subshape = SubshapeID(featureID: featureID, role: "vertex", ordinal: ordinal)
            subshapes[subshape] = .vertex(vertex.id)
            drafts.append(LineageDraft(output: subshape, parents: Array(vertex.parents).sorted()))
        }
        var parentUseCount: [SubshapeID: Int] = [:]
        for draft in drafts {
            for parent in draft.parents {
                parentUseCount[parent, default: 0] += 1
            }
        }
        let lineage = Dictionary(uniqueKeysWithValues: drafts.map { draft in
            let relation: TopologyLineageRelation
            if draft.parents.isEmpty {
                relation = .generated
            } else if draft.parents.count > 1 {
                relation = .merged
            } else if parentUseCount[draft.parents[0], default: 0] > 1 {
                relation = .split
            } else {
                relation = .preserved
            }
            let entry = TopologyLineage(
                output: draft.output,
                parents: draft.parents,
                relation: relation
            )
            return (draft.output, entry)
        })
        return IdentityResult(subshapes: subshapes, lineage: lineage)
    }

    private struct VertexRecord {
        let id: VertexID
        let point: Point3D
        var parents: Set<SubshapeID>
    }

    private struct EdgeRecord {
        let id: EdgeID
        let startVertexID: VertexID
        let endVertexID: VertexID
        let samples: [Point3D]
        var orientations: [Orientation]
        var parents: Set<SubshapeID>
        var stableIDs: Set<String>
    }

    private struct FaceRecord {
        let id: FaceID
        let parents: [SubshapeID]
    }

    private struct EdgeUse {
        let edgeID: EdgeID
        let orientation: Orientation
    }

    private struct LineageDraft {
        let output: SubshapeID
        let parents: [SubshapeID]
    }

    private struct IdentityResult {
        let subshapes: [SubshapeID: TopologyReference]
        let lineage: [SubshapeID: TopologyLineage]
    }
}

import Foundation
import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology

public struct DefaultBRepSewer: BRepSewing {
    public init() {}

    public func sew(
        _ request: BRepSewingRequest,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingResult {
        try request.validate(tolerance: tolerance)
        let draft = try assemble(request, tolerance: tolerance)
        let validatedBRep = try ValidatedBRepModel(
            draft.brep,
            tolerance: tolerance,
            validationLevel: .exact
        )
        return BRepSewingResult(
            validatedBRep: validatedBRep,
            bodyID: draft.bodyID,
            subshapes: draft.subshapes,
            lineage: draft.lineage,
            stableReferences: draft.stableReferences
        )
    }

    private func assemble(
        _ request: BRepSewingRequest,
        tolerance: ModelingTolerance
    ) throws -> BRepSewingDraft {
        var topologyIDs = FeatureTopologyIDAllocator(
            featureID: request.featureID,
            topologyNamespace: request.topologyNamespace
        )
        var model = BRepModel()
        var allVertices: [VertexRecord] = []
        var allEdges: [EdgeRecord] = []
        var allFaces: [FaceRecord] = []
        var generatedShells: [(shell: BRepSewingShell, id: ShellID)] = []
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
                            faceSurface: patch.surface,
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
                            surfaceParameterCurve: use.surfaceParameterCurve
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
            try validateEdgeUses(
                edges,
                bodyKind: request.bodyKind,
                model: model,
                tolerance: tolerance
            )
            let shellID = topologyIDs.nextShellID()
            model.shells[shellID] = Shell(
                id: shellID,
                faceIDs: faceRecords.map(\.id),
                orientation: shell.orientation
            )
            generatedShells.append((shell, shellID))
            allVertices.append(contentsOf: vertices)
            allEdges.append(contentsOf: edges)
            allFaces.append(contentsOf: faceRecords)
        }

        let bodyID = topologyIDs.nextBodyID()
        model.bodies[bodyID] = Body(
            id: bodyID,
            topology: try bodyTopology(
                requestTopology: request.bodyTopology,
                generatedShells: generatedShells,
                tolerance: tolerance
            )
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
        return BRepSewingDraft(
            brep: model,
            bodyID: bodyID,
            subshapes: identity.subshapes,
            lineage: identity.lineage,
            stableReferences: stableReferences
        )
    }

    private func bodyTopology(
        requestTopology: BRepSewingBodyTopology,
        generatedShells: [(shell: BRepSewingShell, id: ShellID)],
        tolerance: ModelingTolerance
    ) throws -> BodyTopology {
        let shellIDsByStableID = Dictionary(uniqueKeysWithValues: generatedShells.map {
            ($0.shell.stableID, $0.id)
        })
        func shellID(for stableID: String) throws -> ShellID {
            guard let shellID = shellIDsByStableID[stableID] else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    tolerance: tolerance,
                    message: "Sewing topology references an unavailable stable shell identity."
                )
            }
            return shellID
        }
        switch requestTopology {
        case .sheet(let shellStableIDs):
            return .sheet(shellIDs: try shellStableIDs.map {
                try shellID(for: $0)
            })
        case .solid(let components):
            return .solid(components: try components.map { component in
                SolidShellComponent(
                    outerShellID: try shellID(for: component.outerShellStableID),
                    voidShellIDs: try component.voidShellStableIDs.map {
                        try shellID(for: $0)
                    }
                )
            })
        }
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
        faceSurface: Surface3D,
        startVertexID: VertexID,
        endVertexID: VertexID,
        records: inout [EdgeRecord],
        model: inout BRepModel,
        topologyIDs: inout FeatureTopologyIDAllocator,
        tolerance: ModelingTolerance
    ) throws -> EdgeUse {
        for index in records.indices {
            let orientation: Orientation
            if records[index].startVertexID == startVertexID,
               records[index].endVertexID == endVertexID {
                orientation = .forward
            } else if records[index].startVertexID == endVertexID,
                      records[index].endVertexID == startVertexID {
                orientation = .reversed
            } else {
                continue
            }
            guard try isProvablySameCurveSpan(
                CurveSpanDefinition(sewingEdge),
                record: records[index].span,
                orientation: orientation,
                tolerance: tolerance
            ) else {
                continue
            }
            records[index].orientations.append(orientation)
            records[index].parents.formUnion(sewingEdge.parentSubshapeIDs)
            records[index].stableIDs.insert(sewingEdge.stableID)
            return EdgeUse(
                edgeID: records[index].id,
                orientation: orientation,
                surfaceParameterCurve: try canonicalSurfaceParameterCurve(
                    sewingEdge.surfaceParameterCurve,
                    candidateCurve: sewingEdge.curve,
                    canonicalSpan: records[index].span,
                    faceSurface: faceSurface,
                    orientation: orientation,
                    tolerance: tolerance
                )
            )
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
            span: CurveSpanDefinition(sewingEdge),
            orientations: [.forward],
            parents: Set(sewingEdge.parentSubshapeIDs),
            stableIDs: [sewingEdge.stableID]
        ))
        return EdgeUse(
            edgeID: edgeID,
            orientation: .forward,
            surfaceParameterCurve: sewingEdge.surfaceParameterCurve
        )
    }

    private func canonicalSurfaceParameterCurve(
        _ parameterCurve: SurfaceParameterCurve,
        candidateCurve: Curve3D,
        canonicalSpan: CurveSpanDefinition,
        faceSurface: Surface3D,
        orientation: Orientation,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        guard case let .certifiedImplicit(candidatePcurve) = parameterCurve,
              case let .implicit(candidateIntersection) = candidateCurve,
              case let .implicit(canonicalIntersection) = canonicalSpan.curve else {
            return parameterCurve
        }
        guard candidatePcurve.intersection == candidateIntersection,
              try candidateIntersection.certifiesSameComponent(
                  as: canonicalIntersection,
                  tolerance: tolerance
              ) else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A reused implicit sewing edge has no transferable pcurve certificate."
            )
        }
        let role: SurfaceIntersectionSurfaceRole
        if faceSurface == .bSpline(canonicalIntersection.firstSurface) {
            role = .first
        } else if faceSurface == .bSpline(canonicalIntersection.secondSurface) {
            role = .second
        } else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: tolerance,
                message: "A reused implicit sewing edge does not contain the coedge face surface."
            )
        }
        let startFraction: Double
        let endFraction: Double
        switch orientation {
        case .forward:
            startFraction = canonicalSpan.startParameter
            endFraction = canonicalSpan.endParameter
        case .reversed:
            startFraction = canonicalSpan.endParameter
            endFraction = canonicalSpan.startParameter
        }
        return .certifiedImplicit(try CertifiedImplicitSurfaceParameterCurve(
            intersection: canonicalIntersection,
            role: role,
            startFraction: startFraction,
            endFraction: endFraction,
            tolerance: tolerance
        ))
    }

    private func isProvablySameCurveSpan(
        _ edge: CurveSpanDefinition,
        record: CurveSpanDefinition,
        orientation: Orientation,
        tolerance: ModelingTolerance
    ) throws -> Bool {
        try CurveSpanCoincidenceMatcher().matches(
            edge,
            record,
            orientation: orientation,
            tolerance: tolerance
        )
    }

    private func validateEdgeUses(
        _ edges: [EdgeRecord],
        bodyKind: BodyKind,
        model: BRepModel,
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
                    let start = model.vertices[edge.startVertexID]?.point
                    let end = model.vertices[edge.endVertexID]?.point
                    throw KernelError(
                        phase: .topology,
                        code: edge.orientations.count > 2 ? .nonManifoldResult : .topologyFailure,
                        tolerance: tolerance,
                        message: "Solid sewing edge \(edge.stableIDs.sorted()) from \(String(describing: start)) to \(String(describing: end)) has \(edge.orientations.count) uses with \(forwardCount) forward and \(reversedCount) reversed."
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
        let span: CurveSpanDefinition
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
        let surfaceParameterCurve: SurfaceParameterCurve
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

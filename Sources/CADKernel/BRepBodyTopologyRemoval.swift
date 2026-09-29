import CADCore
import CADIR
import CADTopology

/// Takes an operand body out of a model that a feature consumes, and names the subshapes that
/// referred to it.
struct BRepBodyTopologyRemoval {
    /// The subshapes naming any topology of `bodyID`.
    func subshapeIDs(
        bodyID: BodyID,
        in model: BRepModel,
        subshapes: [SubshapeID: TopologyReference]
    ) -> Set<SubshapeID> {
        let references = topologyReferences(for: bodyID, in: model)
        return Set(subshapes.compactMap { subshapeID, reference in
            references.contains(reference) ? subshapeID : nil
        })
    }

    private func topologyReferences(for bodyID: BodyID, in model: BRepModel) -> Set<TopologyReference> {
        guard let body = model.bodies[bodyID] else {
            return []
        }
        var references: Set<TopologyReference> = [.body(bodyID)]
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                continue
            }
            for faceID in shell.faceIDs {
                references.insert(.face(faceID))
                guard let face = model.faces[faceID] else {
                    continue
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        continue
                    }
                    for orientedEdge in loop.edges {
                        references.insert(.edge(orientedEdge.edgeID))
                        guard let edge = model.edges[orientedEdge.edgeID] else {
                            continue
                        }
                        references.insert(.vertex(edge.startVertexID))
                        references.insert(.vertex(edge.endVertexID))
                    }
                }
            }
        }
        return references
    }

    /// Removes `bodyID` with its shells, faces, loops, edges, vertices, and geometry.
    func remove(bodyID: BodyID, from model: inout BRepModel) throws {
        guard let body = model.bodies.removeValue(forKey: bodyID) else {
            throw TopologyError.missingReference("Missing boolean body \(bodyID).")
        }
        var surfaceIDs = Set<SurfaceID>()
        var curveIDs = Set<CurveID>()
        var loopIDs = Set<LoopID>()
        var edgeIDs = Set<EdgeID>()
        var vertexIDs = Set<VertexID>()

        for shellID in body.shellIDs {
            guard let shell = model.shells.removeValue(forKey: shellID) else {
                throw TopologyError.missingReference("Missing boolean shell \(shellID).")
            }
            for faceID in shell.faceIDs {
                guard let face = model.faces.removeValue(forKey: faceID) else {
                    throw TopologyError.missingReference("Missing boolean face \(faceID).")
                }
                surfaceIDs.insert(face.surfaceID)
                for loopID in face.loops {
                    loopIDs.insert(loopID)
                }
            }
        }
        for loopID in loopIDs {
            guard let loop = model.loops.removeValue(forKey: loopID) else {
                throw TopologyError.missingReference("Missing boolean loop \(loopID).")
            }
            for orientedEdge in loop.edges {
                edgeIDs.insert(orientedEdge.edgeID)
            }
        }
        for edgeID in edgeIDs {
            guard let edge = model.edges.removeValue(forKey: edgeID) else {
                throw TopologyError.missingReference("Missing boolean edge \(edgeID).")
            }
            curveIDs.insert(edge.curveID)
            vertexIDs.insert(edge.startVertexID)
            vertexIDs.insert(edge.endVertexID)
        }
        for vertexID in vertexIDs {
            model.vertices.removeValue(forKey: vertexID)
        }
        for curveID in curveIDs {
            model.geometry.curves.removeValue(forKey: curveID)
        }
        for surfaceID in surfaceIDs {
            model.geometry.surfaces.removeValue(forKey: surfaceID)
        }
    }
}

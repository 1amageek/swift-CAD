import CADCore

/// Extracts the ownership-closed topology and geometry for a set of bodies.
///
/// Body submodel extraction is a topology operation. Keeping it in CADTopology
/// lets validation certificates and higher-level modeling features share the
/// same ownership traversal without reversing the package dependency graph.
package struct BRepBodySubmodelExtractor {
    package init() {}

    package func extract(
        bodyIDs: Set<BodyID>,
        from model: BRepModel
    ) throws -> BRepModel {
        var result = BRepModel()

        for bodyID in bodyIDs {
            guard let body = model.bodies[bodyID] else {
                throw TopologyError.missingReference("Missing body \(bodyID).")
            }
            result.bodies[bodyID] = body
            for shellID in body.shellIDs {
                guard let shell = model.shells[shellID] else {
                    throw TopologyError.missingReference("Missing shell \(shellID).")
                }
                result.shells[shellID] = shell
                for faceID in shell.faceIDs {
                    guard let face = model.faces[faceID],
                          let surface = model.geometry.surfaces[face.surfaceID] else {
                        throw TopologyError.missingReference(
                            "Missing face geometry for \(faceID)."
                        )
                    }
                    result.faces[faceID] = face
                    result.geometry.surfaces[face.surfaceID] = surface
                    for loopID in face.loops {
                        guard let loop = model.loops[loopID] else {
                            throw TopologyError.missingReference("Missing loop \(loopID).")
                        }
                        result.loops[loopID] = loop
                        for orientedEdge in loop.edges {
                            let edgeID = orientedEdge.edgeID
                            guard let edge = model.edges[edgeID],
                                  let curve = model.geometry.curves[edge.curveID],
                                  let startVertex = model.vertices[edge.startVertexID],
                                  let endVertex = model.vertices[edge.endVertexID] else {
                                throw TopologyError.missingReference(
                                    "Missing edge geometry for \(edgeID)."
                                )
                            }
                            result.edges[edgeID] = edge
                            result.geometry.curves[edge.curveID] = curve
                            result.vertices[edge.startVertexID] = startVertex
                            result.vertices[edge.endVertexID] = endVertex
                        }
                    }
                }
            }
        }
        return result
    }
}

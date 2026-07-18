import CADCore
import CADIR
import CADTopology

package struct BodyTopologyScope: Sendable {
    package let references: Set<TopologyReference>

    package init(bodyID: BodyID, model: BRepModel) throws {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Body topology scope is missing its body.")
        }
        var collected: Set<TopologyReference> = [.body(bodyID)]
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Body topology scope is missing a shell.")
            }
            for faceID in shell.faceIDs {
                collected.insert(.face(faceID))
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Body topology scope is missing a face.")
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Body topology scope is missing a loop.")
                    }
                    for coedge in loop.coedges {
                        collected.insert(.edge(coedge.edgeID))
                        guard let edge = model.edges[coedge.edgeID] else {
                            throw TopologyError.missingReference("Body topology scope is missing an edge.")
                        }
                        collected.insert(.vertex(edge.startVertexID))
                        collected.insert(.vertex(edge.endVertexID))
                    }
                }
            }
        }
        references = collected
    }

    package func subshapeIDs(in index: SubshapeIndex) -> Set<SubshapeID> {
        Set(index.entries.compactMap { subshapeID, reference in
            references.contains(reference) ? subshapeID : nil
        })
    }
}

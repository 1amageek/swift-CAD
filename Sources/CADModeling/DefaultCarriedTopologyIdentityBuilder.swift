import CADCore
import CADIR
import CADTopology

package struct DefaultCarriedTopologyIdentityBuilder: CarriedTopologyIdentityBuilding {
    package init() {}

    package func identity(
        featureID: FeatureID,
        bodyID: BodyID,
        model: BRepModel,
        context: EvaluationContext
    ) throws -> CarriedTopologyIdentity {
        let references = try topologyReferences(bodyID: bodyID, model: model)
        var subshapes: [SubshapeID: TopologyReference] = [:]
        var lineage: [SubshapeID: TopologyLineage] = [:]
        var ordinals: [String: Int] = [:]
        for entry in references {
            let ordinal = ordinals[entry.role, default: 0]
            ordinals[entry.role] = ordinal + 1
            let output = SubshapeID(featureID: featureID, role: entry.role, ordinal: ordinal)
            subshapes[output] = entry.reference
            let parents = sourceSubshapeIDs(for: entry.reference, context: context)
            let relation: TopologyLineageRelation = switch parents.count {
            case 0: .generated
            case 1: .preserved
            default: .merged
            }
            lineage[output] = TopologyLineage(
                output: output,
                parents: parents,
                relation: relation
            )
        }
        return CarriedTopologyIdentity(subshapes: subshapes, lineage: lineage)
    }

    private func topologyReferences(
        bodyID: BodyID,
        model: BRepModel
    ) throws -> [(role: String, reference: TopologyReference)] {
        guard let body = model.bodies[bodyID] else {
            throw TopologyError.missingReference("Carried topology body is missing.")
        }
        var faceIDs = Set<FaceID>()
        var edgeIDs = Set<EdgeID>()
        var vertexIDs = Set<VertexID>()
        for shellID in body.shellIDs {
            guard let shell = model.shells[shellID] else {
                throw TopologyError.missingReference("Carried topology shell is missing.")
            }
            for faceID in shell.faceIDs {
                faceIDs.insert(faceID)
                guard let face = model.faces[faceID] else {
                    throw TopologyError.missingReference("Carried topology face is missing.")
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw TopologyError.missingReference("Carried topology loop is missing.")
                    }
                    for coedge in loop.coedges {
                        edgeIDs.insert(coedge.edgeID)
                        guard let edge = model.edges[coedge.edgeID] else {
                            throw TopologyError.missingReference("Carried topology edge is missing.")
                        }
                        vertexIDs.insert(edge.startVertexID)
                        vertexIDs.insert(edge.endVertexID)
                    }
                }
            }
        }
        var references: [(role: String, reference: TopologyReference)] = [
            (GeneratedSubshapeRole.body.rawValue, .body(bodyID)),
        ]
        references.append(contentsOf: faceIDs.sorted().map {
            (GeneratedSubshapeRole.face.rawValue, .face($0))
        })
        references.append(contentsOf: edgeIDs.sorted().map {
            (GeneratedSubshapeRole.edge.rawValue, .edge($0))
        })
        references.append(contentsOf: vertexIDs.sorted().map {
            (GeneratedSubshapeRole.vertex.rawValue, .vertex($0))
        })
        return references
    }

    private func sourceSubshapeIDs(
        for reference: TopologyReference,
        context: EvaluationContext
    ) -> [SubshapeID] {
        context.subshapeIDs(for: reference)
    }
}

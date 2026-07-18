import CADCore
import CADTopology

public struct SubshapeIndex: Codable, Equatable, Sendable {
    public var entries: [SubshapeID: TopologyReference]

    public init(_ entries: [SubshapeID: TopologyReference] = [:]) {
        self.entries = entries
    }

    public subscript(_ subshapeID: SubshapeID) -> TopologyReference? {
        get { entries[subshapeID] }
        set { entries[subshapeID] = newValue }
    }

    public func reference(for subshapeID: SubshapeID) throws -> TopologyReference {
        guard subshapeID.isValid else {
            throw KernelError(
                phase: .validation,
                code: .invalidInput,
                subshapeID: subshapeID,
                tolerance: nil,
                message: "Subshape lookup requires a valid identity."
            )
        }
        guard let reference = entries[subshapeID] else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                subshapeID: subshapeID,
                tolerance: nil,
                message: "Subshape identity has no live topology reference."
            )
        }
        return reference
    }

    public func validate(
        against model: BRepModel,
        lineage: [SubshapeID: TopologyLineage]
    ) throws {
        var indexedReferences = Set<TopologyReference>()
        for (subshapeID, reference) in entries {
            guard subshapeID.isValid,
                  lineage[subshapeID]?.output == subshapeID else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    featureID: subshapeID.featureID,
                    subshapeID: subshapeID,
                    tolerance: nil,
                    message: "Subshape index entry has no matching lineage output."
                )
            }
            guard indexedReferences.insert(reference).inserted else {
                throw KernelError(
                    phase: .topology,
                    code: .ambiguousSelection,
                    featureID: subshapeID.featureID,
                    subshapeID: subshapeID,
                    tolerance: nil,
                    message: "Live topology is indexed by more than one subshape identity."
                )
            }
            guard contains(reference, in: model) else {
                throw KernelError(
                    phase: .topology,
                    code: .missingReference,
                    featureID: subshapeID.featureID,
                    subshapeID: subshapeID,
                    tolerance: nil,
                    message: "Subshape index references topology outside the evaluated B-rep."
                )
            }
        }
        let expectedReferences = Set(model.bodies.keys.map(TopologyReference.body))
            .union(model.faces.keys.map(TopologyReference.face))
            .union(model.edges.keys.map(TopologyReference.edge))
            .union(model.vertices.keys.map(TopologyReference.vertex))
        guard indexedReferences == expectedReferences else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: nil,
                message: "Subshape index does not cover the evaluated B-rep exactly."
            )
        }
    }

    private func contains(_ reference: TopologyReference, in model: BRepModel) -> Bool {
        switch reference {
        case let .body(bodyID): model.bodies[bodyID] != nil
        case let .face(faceID): model.faces[faceID] != nil
        case let .edge(edgeID): model.edges[edgeID] != nil
        case let .vertex(vertexID): model.vertices[vertexID] != nil
        }
    }
}

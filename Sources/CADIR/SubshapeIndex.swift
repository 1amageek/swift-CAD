import HashTreeCollections
import CADCore
import CADGeometry
import CADTopology

public struct SubshapeIndex: Equatable, Sendable {
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
        var execution = try OriginalQueryExecution.independentGeometry()
        try validate(against: model, lineage: lineage, using: &execution)
    }

    public func validate(
        against model: BRepModel,
        lineage: [SubshapeID: TopologyLineage],
        using execution: inout OriginalQueryExecution
    ) throws {
        try execution.checkpoint()
        var indexedReferences = Set<TopologyReference>()
        for (subshapeID, reference) in entries {
            try execution.consumeWork(1)
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
            try execution.retainStorage(count: 1, stride: MemoryLayout<TopologyReference>.stride)
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
        var expectedReferences = Set<TopologyReference>()
        for id in model.bodies.keys {
            try execution.consumeWork(1)
            try execution.retainStorage(count: 1, stride: MemoryLayout<TopologyReference>.stride)
            expectedReferences.insert(.body(id))
        }
        for id in model.faces.keys {
            try execution.consumeWork(1)
            try execution.retainStorage(count: 1, stride: MemoryLayout<TopologyReference>.stride)
            expectedReferences.insert(.face(id))
        }
        for id in model.edges.keys {
            try execution.consumeWork(1)
            try execution.retainStorage(count: 1, stride: MemoryLayout<TopologyReference>.stride)
            expectedReferences.insert(.edge(id))
        }
        for id in model.vertices.keys {
            try execution.consumeWork(1)
            try execution.retainStorage(count: 1, stride: MemoryLayout<TopologyReference>.stride)
            expectedReferences.insert(.vertex(id))
        }
        try execution.consumeWork(indexedReferences.count)
        guard indexedReferences == expectedReferences else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                tolerance: nil,
                message: "Subshape index does not cover the evaluated B-rep exactly."
            )
        }
        try execution.checkpoint()
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

#if !hasFeature(Embedded)
extension SubshapeIndex: Codable {}
#endif

import HashTreeCollections
import CADCore
import CADIR
import CADTopology

/// Deterministic provenance-first stable selection resolver.
public struct StableSubshapeResolver: StableSubshapeResolving {
    public init() {}

    public func topologyReference(
        for reference: StableSubshapeReference,
        model: BRepModel,
        subshapes: SubshapeIndex,
        lineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance
    ) throws -> TopologyReference {
        try reference.validate()
        try CurrentTaskCancellationChecker().checkCancellation()
        if let direct = subshapes[reference.subshapeID] {
            try requireLive(direct, model: model, tolerance: tolerance)
            guard isCompatible(reference.geometrySignature, with: direct) else {
                throw KernelError(
                    phase: .validation,
                    code: .invalidInput,
                    subshapeID: reference.subshapeID,
                    tolerance: tolerance,
                    message: "Stable subshape identity and geometry signature have different topology kinds."
                )
            }
            return direct
        }

        let lineageCandidates = try liveLineageDescendants(
            of: reference,
            subshapes: subshapes,
            lineage: lineage,
            tolerance: tolerance
        )
        for candidate in lineageCandidates {
            try CurrentTaskCancellationChecker().checkCancellation()
            try requireLive(candidate, model: model, tolerance: tolerance)
        }
        let orderedLineageCandidates = lineageCandidates.sorted(by: topologyOrder)
        if let candidate = orderedLineageCandidates.first {
            guard orderedLineageCandidates.count == 1 else {
                throw ambiguity(reference, tolerance: tolerance, message: "Feature selection lineage has multiple live descendants.")
            }
            return candidate
        }

        let signatureBuilder = SubshapeGeometrySignatureBuilder(model: model, tolerance: tolerance)
        let geometryCandidates = try subshapes.entries.compactMap { candidateID, topologyReference -> TopologyReference? in
            try CurrentTaskCancellationChecker().checkCancellation()
            guard candidateID.featureID == reference.subshapeID.featureID else {
                return nil
            }
            guard isCompatible(reference.geometrySignature, with: topologyReference) else {
                return nil
            }
            let signature = try signatureBuilder.signature(for: topologyReference)
            return signatureBuilder.matches(reference.geometrySignature, signature) ? topologyReference : nil
        }.sorted(by: topologyOrder)
        guard let candidate = geometryCandidates.first else {
            throw KernelError(
                phase: .evaluation,
                code: .missingReference,
                subshapeID: reference.subshapeID,
                tolerance: tolerance,
                message: "Feature selection has no live lineage or geometry match."
            )
        }
        guard geometryCandidates.count == 1 else {
            throw ambiguity(reference, tolerance: tolerance, message: "Feature geometry signature has multiple live candidates.")
        }
        return candidate
    }

    private func liveLineageDescendants(
        of reference: StableSubshapeReference,
        subshapes: SubshapeIndex,
        lineage: [SubshapeID: TopologyLineage],
        tolerance: ModelingTolerance
    ) throws -> Set<TopologyReference> {
        var children: [SubshapeID: [SubshapeID]] = [:]
        for (output, entry) in lineage {
            try CurrentTaskCancellationChecker().checkCancellation()
            guard output == entry.output, entry.isStructurallyValid else {
                throw KernelError(
                    phase: .topology,
                    code: .topologyFailure,
                    featureID: output.featureID,
                    subshapeID: output,
                    tolerance: tolerance,
                    message: "Stable selection lineage contains a structurally invalid entry."
                )
            }
            for parent in entry.parents {
                children[parent, default: []].append(output)
            }
        }
        for parent in Array(children.keys) {
            children[parent] = Array(Set(children[parent, default: []])).sorted()
        }

        var candidates = Set<TopologyReference>()
        var active = Set<SubshapeID>()
        var completed = Set<SubshapeID>()
        var pending: [(id: SubshapeID, exiting: Bool)] = [(reference.subshapeID, false)]
        while let step = pending.popLast() {
            try CurrentTaskCancellationChecker().checkCancellation()
            if step.exiting {
                active.remove(step.id)
                completed.insert(step.id)
                continue
            }
            guard !completed.contains(step.id) else { continue }
            guard active.insert(step.id).inserted else {
                throw KernelError(phase: .topology, code: .topologyFailure,
                    featureID: step.id.featureID, subshapeID: step.id, tolerance: tolerance,
                    message: "Stable selection lineage contains a reachable cycle.")
            }
            pending.append((step.id, true))
            for child in children[step.id, default: []].reversed() {
                if let topology = subshapes[child],
                   isCompatible(reference.geometrySignature, with: topology) {
                    candidates.insert(topology)
                }
                pending.append((child, false))
            }
        }
        return candidates
    }

    package func requireLive(_ reference: TopologyReference, model: BRepModel,
                             tolerance: ModelingTolerance) throws {
        let exists: Bool
        switch reference {
        case .body(let id): exists = model.bodies[id] != nil
        case .face(let id): exists = model.faces[id] != nil
        case .edge(let id): exists = model.edges[id] != nil
        case .vertex(let id): exists = model.vertices[id] != nil
        }
        guard exists else {
            throw KernelError(phase: .topology, code: .missingReference, tolerance: tolerance,
                              message: "Stable selection names topology absent from the current B-rep.")
        }
    }

    package func isCompatible(
        _ signature: SubshapeGeometrySignature,
        with topologyReference: TopologyReference
    ) -> Bool {
        switch (signature, topologyReference) {
        case (.body, .body), (.face, .face), (.edge, .edge), (.vertex, .vertex):
            return true
        default:
            return false
        }
    }

    private func topologyOrder(_ lhs: TopologyReference, _ rhs: TopologyReference) -> Bool {
        topologyKey(lhs) < topologyKey(rhs)
    }

    private func topologyKey(_ reference: TopologyReference) -> String {
        switch reference {
        case let .body(bodyID): "body:\(bodyID)"
        case let .face(faceID): "face:\(faceID)"
        case let .edge(edgeID): "edge:\(edgeID)"
        case let .vertex(vertexID): "vertex:\(vertexID)"
        }
    }

    package func ambiguity(
        _ reference: StableSubshapeReference,
        tolerance: ModelingTolerance,
        message: String
    ) -> KernelError {
        KernelError(
            phase: .evaluation,
            code: .ambiguousSelection,
            subshapeID: reference.subshapeID,
            tolerance: tolerance,
            message: message
        )
    }

}

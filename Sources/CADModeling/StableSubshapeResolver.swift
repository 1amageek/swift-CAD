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
        if let direct = subshapes[reference.subshapeID] {
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
        let orderedLineageCandidates = lineageCandidates.sorted(by: topologyOrder)
        if let candidate = orderedLineageCandidates.first {
            guard orderedLineageCandidates.count == 1 else {
                throw ambiguity(reference, tolerance: tolerance, message: "Feature selection lineage has multiple live descendants.")
            }
            return candidate
        }

        let signatureBuilder = SubshapeGeometrySignatureBuilder(model: model, tolerance: tolerance)
        let geometryCandidates = try subshapes.entries.values.compactMap { topologyReference -> TopologyReference? in
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
        try collectLiveDescendants(
            from: reference.subshapeID,
            signature: reference.geometrySignature,
            children: children,
            subshapes: subshapes,
            tolerance: tolerance,
            active: &active,
            completed: &completed,
            candidates: &candidates
        )
        return candidates
    }

    private func collectLiveDescendants(
        from current: SubshapeID,
        signature: SubshapeGeometrySignature,
        children: [SubshapeID: [SubshapeID]],
        subshapes: SubshapeIndex,
        tolerance: ModelingTolerance,
        active: inout Set<SubshapeID>,
        completed: inout Set<SubshapeID>,
        candidates: inout Set<TopologyReference>
    ) throws {
        guard completed.contains(current) == false else { return }
        guard active.insert(current).inserted else {
            throw KernelError(
                phase: .topology,
                code: .topologyFailure,
                featureID: current.featureID,
                subshapeID: current,
                tolerance: tolerance,
                message: "Stable selection lineage contains a reachable cycle."
            )
        }
        for child in children[current, default: []] {
            if let topologyReference = subshapes[child],
               isCompatible(signature, with: topologyReference) {
                candidates.insert(topologyReference)
            }
            try collectLiveDescendants(
                from: child,
                signature: signature,
                children: children,
                subshapes: subshapes,
                tolerance: tolerance,
                active: &active,
                completed: &completed,
                candidates: &candidates
            )
        }
        active.remove(current)
        completed.insert(current)
    }

    private func isCompatible(
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

    private func ambiguity(
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

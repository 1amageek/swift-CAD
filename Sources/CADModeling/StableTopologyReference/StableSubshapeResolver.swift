import HashTreeCollections
import CADCore
import CADGeometry
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try topologyReference(for: reference, model: model, subshapes: subshapes,
            lineage: lineage, tolerance: tolerance, maximumSubdivisionDepth: 32,
            remainingSourceDepth: 16, maximumAlgebraicDepth: 32, using: &execution)
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

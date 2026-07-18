import CADCore
import CADIR
import CADModeling

extension EvaluatedDocument {
    public func stableSubshapeReference(
        for subshapeID: SubshapeID
    ) throws -> StableSubshapeReference {
        let topologyReference = try subshapes.reference(for: subshapeID)
        let reference = StableSubshapeReference(
            subshapeID: subshapeID,
            geometrySignature: try SubshapeGeometrySignatureBuilder(
                model: brep,
                tolerance: configuration.tolerance
            ).signature(for: topologyReference)
        )
        try reference.validate()
        return reference
    }

    public func topologyReference(
        for reference: StableSubshapeReference
    ) throws -> TopologyReference {
        try StableSubshapeResolver().topologyReference(
            for: reference,
            model: brep,
            subshapes: subshapes,
            lineage: lineage,
            tolerance: configuration.tolerance
        )
    }

}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.StableSubshapeReference`.
extension CADIR.StableSubshapeReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.StableSubshapeReference", fields: 2)
        try encoder.field("geometrySignature", geometrySignature)
        try encoder.field("subshapeID", subshapeID)
    }
}

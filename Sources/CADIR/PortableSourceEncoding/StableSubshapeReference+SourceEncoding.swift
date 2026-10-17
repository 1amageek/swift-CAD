import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.StableSubshapeReference`.
extension CADIR.StableSubshapeReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.StableSubshapeReference", fields: 2, using: &admission)
        try encoder.field("geometrySignature", geometrySignature, using: &admission)
        try encoder.field("subshapeID", subshapeID, using: &admission)
    }
}

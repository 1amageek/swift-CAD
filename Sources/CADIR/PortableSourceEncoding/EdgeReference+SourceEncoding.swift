import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeReference`.
extension CADIR.EdgeReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.EdgeReference", fields: 1, using: &admission)
        try encoder.field("subshape", subshape, using: &admission)
    }
}

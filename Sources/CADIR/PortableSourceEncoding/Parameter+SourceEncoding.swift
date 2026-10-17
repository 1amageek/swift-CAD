import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.Parameter`.
extension CADIR.Parameter: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.Parameter", fields: 4, using: &admission)
        try encoder.field("expression", expression, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("kind", kind, using: &admission)
        try encoder.field("name", name, using: &admission)
    }
}

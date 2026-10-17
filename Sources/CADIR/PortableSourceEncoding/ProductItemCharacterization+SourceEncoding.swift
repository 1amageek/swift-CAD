import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductItemCharacterization`.
extension CADIR.ProductItemCharacterization: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductItemCharacterization", fields: 3, using: &admission)
        try encoder.field("description", description, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}

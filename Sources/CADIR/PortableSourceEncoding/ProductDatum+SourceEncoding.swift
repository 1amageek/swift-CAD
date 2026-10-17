import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductDatum`.
extension CADIR.ProductDatum: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductDatum", fields: 5, using: &admission)
        try encoder.field("description", description, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("identification", identification, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}

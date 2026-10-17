import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SelectionDimension`.
extension CADIR.SelectionDimension: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SelectionDimension", fields: 6, using: &admission)
        try encoder.field("first", first, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("kind", kind, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("second", second, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}

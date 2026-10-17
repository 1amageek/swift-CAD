import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ColorRGBA`.
extension CADIR.ColorRGBA: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ColorRGBA", fields: 4, using: &admission)
        try encoder.field("a", a, using: &admission)
        try encoder.field("b", b, using: &admission)
        try encoder.field("g", g, using: &admission)
        try encoder.field("r", r, using: &admission)
    }
}

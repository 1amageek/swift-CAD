import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ColorRGBA`.
extension CADIR.ColorRGBA: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ColorRGBA", fields: 4)
        try encoder.field("a", a)
        try encoder.field("b", b)
        try encoder.field("g", g)
        try encoder.field("r", r)
    }
}

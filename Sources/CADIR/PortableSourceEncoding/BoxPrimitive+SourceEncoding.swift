import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BoxPrimitive`.
extension CADIR.BoxPrimitive: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.BoxPrimitive", fields: 4)
        try encoder.field("depth", depth)
        try encoder.field("height", height)
        try encoder.field("placement", placement)
        try encoder.field("width", width)
    }
}

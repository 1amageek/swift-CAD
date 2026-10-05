import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.WrapOptions`.
extension CADIR.WrapOptions: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.WrapOptions", fields: 10)
        try encoder.field("flipsNormal", flipsNormal)
        try encoder.field("flipsUV", flipsUV)
        try encoder.field("mirrors", mirrors)
        try encoder.field("offsetN", offsetN)
        try encoder.field("offsetU", offsetU)
        try encoder.field("offsetV", offsetV)
        try encoder.field("reblends", reblends)
        try encoder.field("scaleN", scaleN)
        try encoder.field("scaleU", scaleU)
        try encoder.field("scaleV", scaleV)
    }
}

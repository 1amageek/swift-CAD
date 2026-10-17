import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.WrapOptions`.
extension CADIR.WrapOptions: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.WrapOptions", fields: 10, using: &admission)
        try encoder.field("flipsNormal", flipsNormal, using: &admission)
        try encoder.field("flipsUV", flipsUV, using: &admission)
        try encoder.field("mirrors", mirrors, using: &admission)
        try encoder.field("offsetN", offsetN, using: &admission)
        try encoder.field("offsetU", offsetU, using: &admission)
        try encoder.field("offsetV", offsetV, using: &admission)
        try encoder.field("reblends", reblends, using: &admission)
        try encoder.field("scaleN", scaleN, using: &admission)
        try encoder.field("scaleU", scaleU, using: &admission)
        try encoder.field("scaleV", scaleV, using: &admission)
    }
}

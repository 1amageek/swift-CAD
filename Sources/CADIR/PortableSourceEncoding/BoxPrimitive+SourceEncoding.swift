import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BoxPrimitive`.
extension CADIR.BoxPrimitive: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.BoxPrimitive", fields: 4, using: &admission)
        try encoder.field("depth", depth, using: &admission)
        try encoder.field("height", height, using: &admission)
        try encoder.field("placement", placement, using: &admission)
        try encoder.field("width", width, using: &admission)
    }
}

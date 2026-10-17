import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ConePrimitive`.
extension CADIR.ConePrimitive: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ConePrimitive", fields: 3, using: &admission)
        try encoder.field("baseRadius", baseRadius, using: &admission)
        try encoder.field("height", height, using: &admission)
        try encoder.field("placement", placement, using: &admission)
    }
}

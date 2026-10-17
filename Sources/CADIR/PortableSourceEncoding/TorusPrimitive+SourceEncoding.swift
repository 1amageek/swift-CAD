import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.TorusPrimitive`.
extension CADIR.TorusPrimitive: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.TorusPrimitive", fields: 3, using: &admission)
        try encoder.field("majorRadius", majorRadius, using: &admission)
        try encoder.field("minorRadius", minorRadius, using: &admission)
        try encoder.field("placement", placement, using: &admission)
    }
}

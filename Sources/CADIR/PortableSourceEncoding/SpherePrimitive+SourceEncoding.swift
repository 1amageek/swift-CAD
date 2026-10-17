import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SpherePrimitive`.
extension CADIR.SpherePrimitive: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SpherePrimitive", fields: 2, using: &admission)
        try encoder.field("placement", placement, using: &admission)
        try encoder.field("radius", radius, using: &admission)
    }
}

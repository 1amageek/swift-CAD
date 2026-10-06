import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SpherePrimitive`.
extension CADIR.SpherePrimitive: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SpherePrimitive", fields: 2)
        try encoder.field("placement", placement)
        try encoder.field("radius", radius)
    }
}

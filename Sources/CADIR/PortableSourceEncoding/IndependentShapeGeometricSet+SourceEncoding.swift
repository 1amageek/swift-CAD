import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeGeometricSet`.
extension CADIR.IndependentShapeGeometricSet: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeGeometricSet", fields: 4)
        try encoder.field("family", family)
        try encoder.field("id", id)
        try encoder.field("members", members)
        try encoder.field("name", name)
    }
}

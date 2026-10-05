import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.Plane3D`.
extension CADGeometry.Plane3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.Plane3D", fields: 3)
        try encoder.field("normal", normal)
        try encoder.field("origin", origin)
        try encoder.field("uDirection", uDirection)
    }
}

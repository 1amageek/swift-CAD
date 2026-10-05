import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.Cylinder3D`.
extension CADGeometry.Cylinder3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.Cylinder3D", fields: 3)
        try encoder.field("axis", axis)
        try encoder.field("origin", origin)
        try encoder.field("radius", radius)
    }
}

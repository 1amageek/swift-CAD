import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.Cylinder3D`.
extension CADGeometry.Cylinder3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.Cylinder3D", fields: 3, using: &admission)
        try encoder.field("axis", axis, using: &admission)
        try encoder.field("origin", origin, using: &admission)
        try encoder.field("radius", radius, using: &admission)
    }
}

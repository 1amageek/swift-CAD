import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.Plane3D`.
extension CADGeometry.Plane3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.Plane3D", fields: 3, using: &admission)
        try encoder.field("normal", normal, using: &admission)
        try encoder.field("origin", origin, using: &admission)
        try encoder.field("uDirection", uDirection, using: &admission)
    }
}

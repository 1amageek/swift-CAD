import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.Circle3D`.
extension CADGeometry.Circle3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.Circle3D", fields: 3, using: &admission)
        try encoder.field("center", center, using: &admission)
        try encoder.field("normal", normal, using: &admission)
        try encoder.field("radius", radius, using: &admission)
    }
}

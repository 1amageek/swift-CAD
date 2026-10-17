import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.Parabola3D`.
extension CADGeometry.Parabola3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.Parabola3D", fields: 4, using: &admission)
        try encoder.field("axis", axis, using: &admission)
        try encoder.field("focalLength", focalLength, using: &admission)
        try encoder.field("normal", normal, using: &admission)
        try encoder.field("vertex", vertex, using: &admission)
    }
}

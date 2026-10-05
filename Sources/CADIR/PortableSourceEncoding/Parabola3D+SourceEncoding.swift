import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.Parabola3D`.
extension CADGeometry.Parabola3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.Parabola3D", fields: 4)
        try encoder.field("axis", axis)
        try encoder.field("focalLength", focalLength)
        try encoder.field("normal", normal)
        try encoder.field("vertex", vertex)
    }
}

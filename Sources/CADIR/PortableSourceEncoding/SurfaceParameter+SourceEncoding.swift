import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.SurfaceParameter`.
extension CADGeometry.SurfaceParameter: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.SurfaceParameter", fields: 2)
        try encoder.field("u", u)
        try encoder.field("v", v)
    }
}

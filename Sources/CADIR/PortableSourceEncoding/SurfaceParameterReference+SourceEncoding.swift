import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceParameterReference`.
extension CADIR.SurfaceParameterReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceParameterReference", fields: 3)
        try encoder.field("surface", surface)
        try encoder.field("u", u)
        try encoder.field("v", v)
    }
}

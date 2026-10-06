import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BSplineSurfaceFeature`.
extension CADIR.BSplineSurfaceFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.BSplineSurfaceFeature", fields: 3)
        try encoder.field("material", material)
        try encoder.field("parameterDomain", parameterDomain)
        try encoder.field("surface", surface)
    }
}

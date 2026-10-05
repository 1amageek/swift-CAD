import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceExtendFeature`.
extension CADIR.SurfaceExtendFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceExtendFeature", fields: 3)
        try encoder.field("target", target)
        try encoder.field("uDomain", uDomain)
        try encoder.field("vDomain", vDomain)
    }
}

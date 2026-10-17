import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceExtendFeature`.
extension CADIR.SurfaceExtendFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceExtendFeature", fields: 3, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("uDomain", uDomain, using: &admission)
        try encoder.field("vDomain", vDomain, using: &admission)
    }
}

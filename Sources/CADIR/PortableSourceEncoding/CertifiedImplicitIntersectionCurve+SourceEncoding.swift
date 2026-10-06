import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedImplicitIntersectionCurve`.
extension CADGeometry.CertifiedImplicitIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedImplicitIntersectionCurve", fields: 5)
        try encoder.field("cells", cells)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("firstSurface", firstSurface)
        try encoder.field("isClosed", isClosed)
        try encoder.field("secondSurface", secondSurface)
    }
}

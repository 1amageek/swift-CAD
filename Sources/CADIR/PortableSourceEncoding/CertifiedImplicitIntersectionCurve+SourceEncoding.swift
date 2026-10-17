import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedImplicitIntersectionCurve`.
extension CADGeometry.CertifiedImplicitIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedImplicitIntersectionCurve", fields: 5, using: &admission)
        try encoder.field("cells", cells, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("firstSurface", firstSurface, using: &admission)
        try encoder.field("isClosed", isClosed, using: &admission)
        try encoder.field("secondSurface", secondSurface, using: &admission)
    }
}

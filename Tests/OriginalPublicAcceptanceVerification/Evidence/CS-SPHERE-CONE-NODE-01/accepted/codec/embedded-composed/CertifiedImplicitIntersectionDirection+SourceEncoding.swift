import CADCore

/// Encodes original source fields owned by `CADGeometry.CertifiedImplicitIntersectionDirection`.
extension CADGeometry.CertifiedImplicitIntersectionDirection: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.CertifiedImplicitIntersectionDirection", caseName: rawValue, values: 0)
    }
}

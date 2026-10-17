import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedImplicitIntersectionDirection`.
extension CADGeometry.CertifiedImplicitIntersectionDirection: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADGeometry.CertifiedImplicitIntersectionDirection", caseName: rawValue, values: 0, using: &admission)
    }
}

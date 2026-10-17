import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedImplicitIntersectionGraphCell`.
extension CADGeometry.CertifiedImplicitIntersectionGraphCell: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedImplicitIntersectionGraphCell", fields: 6, using: &admission)
        try encoder.field("direction", direction, using: &admission)
        try encoder.field("freeParameter", freeParameter, using: &admission)
        try encoder.field("lowerAnchor", lowerAnchor, using: &admission)
        try encoder.field("midpointAnchor", midpointAnchor, using: &admission)
        try encoder.field("parameterBox", parameterBox, using: &admission)
        try encoder.field("upperAnchor", upperAnchor, using: &admission)
    }
}

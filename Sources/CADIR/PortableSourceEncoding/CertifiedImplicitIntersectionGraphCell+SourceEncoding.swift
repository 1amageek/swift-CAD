import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedImplicitIntersectionGraphCell`.
extension CADGeometry.CertifiedImplicitIntersectionGraphCell: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedImplicitIntersectionGraphCell", fields: 6)
        try encoder.field("direction", direction)
        try encoder.field("freeParameter", freeParameter)
        try encoder.field("lowerAnchor", lowerAnchor)
        try encoder.field("midpointAnchor", midpointAnchor)
        try encoder.field("parameterBox", parameterBox)
        try encoder.field("upperAnchor", upperAnchor)
    }
}

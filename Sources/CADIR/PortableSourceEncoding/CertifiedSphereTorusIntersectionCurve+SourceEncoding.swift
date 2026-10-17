import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedSphereTorusIntersectionCurve`.
extension CADGeometry.CertifiedSphereTorusIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedSphereTorusIntersectionCurve", fields: 7, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("componentKind", componentKind, using: &admission)
        try encoder.field("lowerAngle", lowerAngle, using: &admission)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound, using: &admission)
        try encoder.field("sphereSurface", sphereSurface, using: &admission)
        try encoder.field("torusSurface", torusSurface, using: &admission)
        try encoder.field("upperAngle", upperAngle, using: &admission)
    }
}

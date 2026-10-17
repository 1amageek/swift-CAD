import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedPlaneTorusIntersectionCurve`.
extension CADGeometry.CertifiedPlaneTorusIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedPlaneTorusIntersectionCurve", fields: 7, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("componentKind", componentKind, using: &admission)
        try encoder.field("lowerMinorAngle", lowerMinorAngle, using: &admission)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound, using: &admission)
        try encoder.field("planeSurface", planeSurface, using: &admission)
        try encoder.field("torusSurface", torusSurface, using: &admission)
        try encoder.field("upperMinorAngle", upperMinorAngle, using: &admission)
    }
}

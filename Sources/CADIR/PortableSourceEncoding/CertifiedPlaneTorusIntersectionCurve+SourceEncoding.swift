import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedPlaneTorusIntersectionCurve`.
extension CADGeometry.CertifiedPlaneTorusIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedPlaneTorusIntersectionCurve", fields: 7)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("componentKind", componentKind)
        try encoder.field("lowerMinorAngle", lowerMinorAngle)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("planeSurface", planeSurface)
        try encoder.field("torusSurface", torusSurface)
        try encoder.field("upperMinorAngle", upperMinorAngle)
    }
}

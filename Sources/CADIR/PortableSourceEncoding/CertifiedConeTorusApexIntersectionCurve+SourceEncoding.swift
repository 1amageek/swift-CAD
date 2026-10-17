import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedConeTorusApexIntersectionCurve`.
extension CADGeometry.CertifiedConeTorusApexIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedConeTorusApexIntersectionCurve", fields: 7, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("componentKind", componentKind, using: &admission)
        try encoder.field("coneSurface", coneSurface, using: &admission)
        try encoder.field("lowerAngle", lowerAngle, using: &admission)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound, using: &admission)
        try encoder.field("torusSurface", torusSurface, using: &admission)
        try encoder.field("upperAngle", upperAngle, using: &admission)
    }
}

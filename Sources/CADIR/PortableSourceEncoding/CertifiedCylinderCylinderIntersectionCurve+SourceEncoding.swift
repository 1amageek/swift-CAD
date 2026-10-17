import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedCylinderCylinderIntersectionCurve`.
extension CADGeometry.CertifiedCylinderCylinderIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedCylinderCylinderIntersectionCurve", fields: 7, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("componentKind", componentKind, using: &admission)
        try encoder.field("lowerAngle", lowerAngle, using: &admission)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound, using: &admission)
        try encoder.field("parameterizedSurface", parameterizedSurface, using: &admission)
        try encoder.field("referenceSurface", referenceSurface, using: &admission)
        try encoder.field("upperAngle", upperAngle, using: &admission)
    }
}

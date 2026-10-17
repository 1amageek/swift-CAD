import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedParallelTorusCylinderIntersectionCurve`.
extension CADGeometry.CertifiedParallelTorusCylinderIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedParallelTorusCylinderIntersectionCurve", fields: 7, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("componentKind", componentKind, using: &admission)
        try encoder.field("cylinderSurface", cylinderSurface, using: &admission)
        try encoder.field("lowerAngle", lowerAngle, using: &admission)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound, using: &admission)
        try encoder.field("torusSurface", torusSurface, using: &admission)
        try encoder.field("upperAngle", upperAngle, using: &admission)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedGeneralTorusCylinderIntersectionCurve`.
extension CADGeometry.CertifiedGeneralTorusCylinderIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedGeneralTorusCylinderIntersectionCurve", fields: 8, using: &admission)
        try encoder.field("branchCount", branchCount, using: &admission)
        try encoder.field("branchIndex", branchIndex, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("cylinderSurface", cylinderSurface, using: &admission)
        try encoder.field("maximumCellCount", maximumCellCount, using: &admission)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound, using: &admission)
        try encoder.field("maximumSubdivisionDepth", maximumSubdivisionDepth, using: &admission)
        try encoder.field("torusSurface", torusSurface, using: &admission)
    }
}

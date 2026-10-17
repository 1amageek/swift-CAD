import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve`.
extension CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedCongruentTorusTorusIntersectionCurve", fields: 8, using: &admission)
        try encoder.field("bisectorPlaneKind", bisectorPlaneKind, using: &admission)
        try encoder.field("branchCount", branchCount, using: &admission)
        try encoder.field("branchIndex", branchIndex, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound, using: &admission)
        try encoder.field("primarySurface", primarySurface, using: &admission)
        try encoder.field("secondarySurface", secondarySurface, using: &admission)
        try encoder.field("sectionCurve", sectionCurve, using: &admission)
    }
}

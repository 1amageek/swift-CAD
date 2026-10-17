import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedParallelTorusTorusIntersectionCurve`.
extension CADGeometry.CertifiedParallelTorusTorusIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedParallelTorusTorusIntersectionCurve", fields: 9, using: &admission)
        try encoder.field("branchCount", branchCount, using: &admission)
        try encoder.field("branchIndex", branchIndex, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("componentKind", componentKind, using: &admission)
        try encoder.field("maximumCellCount", maximumCellCount, using: &admission)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound, using: &admission)
        try encoder.field("maximumSubdivisionDepth", maximumSubdivisionDepth, using: &admission)
        try encoder.field("primarySurface", primarySurface, using: &admission)
        try encoder.field("secondarySurface", secondarySurface, using: &admission)
    }
}

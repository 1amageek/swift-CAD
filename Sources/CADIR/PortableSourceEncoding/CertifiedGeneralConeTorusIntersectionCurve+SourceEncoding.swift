import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedGeneralConeTorusIntersectionCurve`.
extension CADGeometry.CertifiedGeneralConeTorusIntersectionCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.CertifiedGeneralConeTorusIntersectionCurve", fields: 9)
        try encoder.field("apexReduction", apexReduction)
        try encoder.field("branchCount", branchCount)
        try encoder.field("branchIndex", branchIndex)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("coneSurface", coneSurface)
        try encoder.field("maximumCellCount", maximumCellCount)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound)
        try encoder.field("maximumSubdivisionDepth", maximumSubdivisionDepth)
        try encoder.field("torusSurface", torusSurface)
    }
}

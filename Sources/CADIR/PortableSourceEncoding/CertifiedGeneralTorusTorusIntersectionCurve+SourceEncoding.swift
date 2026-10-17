import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.CertifiedGeneralTorusTorusIntersectionCurve`.
extension CADGeometry.CertifiedGeneralTorusTorusIntersectionCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.CertifiedGeneralTorusTorusIntersectionCurve", fields: 9, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("componentCount", componentCount, using: &admission)
        try encoder.field("componentIndex", componentIndex, using: &admission)
        try encoder.field("maximumIterations", maximumIterations, using: &admission)
        try encoder.field("maximumResidualUpperBound", maximumResidualUpperBound, using: &admission)
        try encoder.field("maximumSeedCount", maximumSeedCount, using: &admission)
        try encoder.field("maximumSubdivisionDepth", maximumSubdivisionDepth, using: &admission)
        try encoder.field("parameterizedSurface", parameterizedSurface, using: &admission)
        try encoder.field("referenceSurface", referenceSurface, using: &admission)
    }
}

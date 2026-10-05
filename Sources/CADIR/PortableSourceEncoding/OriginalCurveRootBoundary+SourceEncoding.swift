import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalCurveRootBoundary`.
extension CADGeometry.OriginalCurveRootBoundary: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalCurveRootBoundary", fields: 9)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("constraint", constraint)
        try encoder.field("excludesLowerEndpoint", excludesLowerEndpoint)
        try encoder.field("excludesUpperEndpoint", excludesUpperEndpoint)
        try encoder.field("isolationDepth", isolationDepth)
        try encoder.field("isolationLower", isolationLower)
        try encoder.field("isolationUpper", isolationUpper)
        try encoder.field("source", source)
        try encoder.field("spanIndex", spanIndex)
    }
}

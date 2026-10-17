import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalCurveRootBoundary`.
extension CADGeometry.OriginalCurveRootBoundary: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalCurveRootBoundary", fields: 9, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("constraint", constraint, using: &admission)
        try encoder.field("excludesLowerEndpoint", excludesLowerEndpoint, using: &admission)
        try encoder.field("excludesUpperEndpoint", excludesUpperEndpoint, using: &admission)
        try encoder.field("isolationDepth", isolationDepth, using: &admission)
        try encoder.field("isolationLower", isolationLower, using: &admission)
        try encoder.field("isolationUpper", isolationUpper, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("spanIndex", spanIndex, using: &admission)
    }
}

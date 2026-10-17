import CADCore
import CADGeometry

/// Retains the unchanged guide traversal and exact original endpoint correction source.
extension CADGeometry.OriginalGuideEndpointConnectorCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalGuideEndpointConnectorCurve3D", fields: 6, using: &admission)
        try encoder.field("correctionBasis", correctionBasis, using: &admission)
        try encoder.field("endAtEnd", endAtEnd, using: &admission)
        try encoder.field("endBoundary", endBoundary, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("startAtEnd", startAtEnd, using: &admission)
        try encoder.field("startBoundary", startBoundary, using: &admission)
    }
}

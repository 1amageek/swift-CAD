import CADCore

/// Retains the unchanged guide traversal and exact original endpoint correction source.
extension CADGeometry.OriginalGuideEndpointConnectorCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalGuideEndpointConnectorCurve3D", fields: 6)
        try encoder.field("correctionBasis", correctionBasis)
        try encoder.field("endAtEnd", endAtEnd)
        try encoder.field("endBoundary", endBoundary)
        try encoder.field("source", source)
        try encoder.field("startAtEnd", startAtEnd)
        try encoder.field("startBoundary", startBoundary)
    }
}

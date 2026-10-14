import CADCore

/// Retains the original connector construction and both endpoint source expressions.
extension CADGeometry.OriginalEndpointConnectorCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalEndpointConnectorCurve3D", fields: 6)
        try encoder.field("construction", construction)
        try encoder.field("correctionBasis", correctionBasis)
        try encoder.field("endAtEnd", endAtEnd)
        try encoder.field("endBoundary", endBoundary)
        try encoder.field("startAtEnd", startAtEnd)
        try encoder.field("startBoundary", startBoundary)
    }
}

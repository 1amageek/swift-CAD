import CADCore

/// Encodes the immutable authored polyline authority, excluding reconstruction policy.
extension CADGeometry.OriginalPolylineCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalPolylineCurve3D", fields: 2)
        try encoder.field("isClosed", isClosed)
        try encoder.field("points", points)
    }
}

import CADCore

/// Retains complete original image authority and excludes prepared caches.
extension OriginalAffineWordCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalAffineWordCurve3D", fields: 2)
        try encoder.field("operationWord", operationWord)
        try encoder.field("source", source)
    }
}

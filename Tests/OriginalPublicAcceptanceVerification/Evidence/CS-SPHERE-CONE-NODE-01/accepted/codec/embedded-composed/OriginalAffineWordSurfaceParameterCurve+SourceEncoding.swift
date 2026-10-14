import CADCore

/// Retains complete original image authority and excludes prepared caches.
extension OriginalAffineWordSurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalAffineWordSurfaceParameterCurve", fields: 4)
        try encoder.field("endFraction", endFraction)
        try encoder.field("source", source)
        try encoder.field("startFraction", startFraction)
        try encoder.field("target", target)
    }
}

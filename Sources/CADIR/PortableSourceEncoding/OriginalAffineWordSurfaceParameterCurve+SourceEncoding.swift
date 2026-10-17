import CADCore
import CADGeometry

/// Retains complete original image authority and excludes prepared caches.
extension OriginalAffineWordSurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalAffineWordSurfaceParameterCurve", fields: 4, using: &admission)
        try encoder.field("endFraction", endFraction, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("startFraction", startFraction, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}

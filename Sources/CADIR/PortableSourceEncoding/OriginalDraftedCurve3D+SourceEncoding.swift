import CADCore
import CADGeometry

/// Encodes original draft source values, excluding derived preparation caches.
extension CADGeometry.OriginalDraftedCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalDraftedCurve3D", fields: 6, using: &admission)
        try encoder.field("angle", angle, using: &admission)
        try encoder.field("axis", axis, using: &admission)
        try encoder.field("generator", generator, using: &admission)
        try encoder.field("height", height, using: &admission)
        try encoder.field("normal", normal, using: &admission)
        try encoder.field("pull", pull, using: &admission)
    }
}

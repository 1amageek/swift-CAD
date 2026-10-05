import CADCore
import CADGeometry

/// Encodes original draft source values, excluding derived preparation caches.
extension CADGeometry.OriginalDraftedCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalDraftedCurve3D", fields: 6)
        try encoder.field("angle", angle)
        try encoder.field("axis", axis)
        try encoder.field("generator", generator)
        try encoder.field("height", height)
        try encoder.field("normal", normal)
        try encoder.field("pull", pull)
    }
}

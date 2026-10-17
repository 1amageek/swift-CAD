import CADCore
import CADGeometry

/// Encodes original draft source values, excluding derived preparation caches.
extension CADGeometry.OriginalDraftedRuledSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalDraftedRuledSurface3D", fields: 2, using: &admission)
        try encoder.field("endHeight", endHeight, using: &admission)
        try encoder.field("start", start, using: &admission)
    }
}

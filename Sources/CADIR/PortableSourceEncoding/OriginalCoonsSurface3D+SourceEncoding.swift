import CADCore
import CADGeometry
import CADTopology

/// Encodes the four original traversals without derived corner caches.
extension CADGeometry.OriginalCoonsSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalCoonsSurface3D", fields: 4, using: &admission)
        try encoder.field("uMaximumBoundary", uMaximumBoundary, using: &admission)
        try encoder.field("uMinimumBoundary", uMinimumBoundary, using: &admission)
        try encoder.field("vMaximumBoundary", vMaximumBoundary, using: &admission)
        try encoder.field("vMinimumBoundary", vMinimumBoundary, using: &admission)
    }
}

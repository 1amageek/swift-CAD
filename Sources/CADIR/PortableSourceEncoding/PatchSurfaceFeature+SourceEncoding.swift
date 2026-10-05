import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PatchSurfaceFeature`.
extension CADIR.PatchSurfaceFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.PatchSurfaceFeature", fields: 9)
        try encoder.field("material", material)
        try encoder.field("uMaximumBoundary", uMaximumBoundary)
        try encoder.field("uMaximumOrientation", uMaximumOrientation)
        try encoder.field("uMinimumBoundary", uMinimumBoundary)
        try encoder.field("uMinimumOrientation", uMinimumOrientation)
        try encoder.field("vMaximumBoundary", vMaximumBoundary)
        try encoder.field("vMaximumOrientation", vMaximumOrientation)
        try encoder.field("vMinimumBoundary", vMinimumBoundary)
        try encoder.field("vMinimumOrientation", vMinimumOrientation)
    }
}

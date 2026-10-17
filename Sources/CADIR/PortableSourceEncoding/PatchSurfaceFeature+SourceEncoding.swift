import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PatchSurfaceFeature`.
extension CADIR.PatchSurfaceFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.PatchSurfaceFeature", fields: 9, using: &admission)
        try encoder.field("material", material, using: &admission)
        try encoder.field("uMaximumBoundary", uMaximumBoundary, using: &admission)
        try encoder.field("uMaximumOrientation", uMaximumOrientation, using: &admission)
        try encoder.field("uMinimumBoundary", uMinimumBoundary, using: &admission)
        try encoder.field("uMinimumOrientation", uMinimumOrientation, using: &admission)
        try encoder.field("vMaximumBoundary", vMaximumBoundary, using: &admission)
        try encoder.field("vMaximumOrientation", vMaximumOrientation, using: &admission)
        try encoder.field("vMinimumBoundary", vMinimumBoundary, using: &admission)
        try encoder.field("vMinimumOrientation", vMinimumOrientation, using: &admission)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BridgeSurfaceFeature`.
extension CADIR.BridgeSurfaceFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.BridgeSurfaceFeature", fields: 12, using: &admission)
        try encoder.field("endBoundary", endBoundary, using: &admission)
        try encoder.field("endContinuity", endContinuity, using: &admission)
        try encoder.field("endOrientation", endOrientation, using: &admission)
        try encoder.field("endTension", endTension, using: &admission)
        try encoder.field("endTransform", endTransform, using: &admission)
        try encoder.field("endWall", endWall, using: &admission)
        try encoder.field("startBoundary", startBoundary, using: &admission)
        try encoder.field("startContinuity", startContinuity, using: &admission)
        try encoder.field("startTension", startTension, using: &admission)
        try encoder.field("startTransform", startTransform, using: &admission)
        try encoder.field("startWall", startWall, using: &admission)
        try encoder.field("width", width, using: &admission)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BridgeSurfaceFeature`.
extension CADIR.BridgeSurfaceFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.BridgeSurfaceFeature", fields: 12)
        try encoder.field("endBoundary", endBoundary)
        try encoder.field("endContinuity", endContinuity)
        try encoder.field("endOrientation", endOrientation)
        try encoder.field("endTension", endTension)
        try encoder.field("endTransform", endTransform)
        try encoder.field("endWall", endWall)
        try encoder.field("startBoundary", startBoundary)
        try encoder.field("startContinuity", startContinuity)
        try encoder.field("startTension", startTension)
        try encoder.field("startTransform", startTransform)
        try encoder.field("startWall", startWall)
        try encoder.field("width", width)
    }
}

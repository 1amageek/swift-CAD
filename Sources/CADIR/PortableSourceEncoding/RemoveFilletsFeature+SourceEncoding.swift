import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.RemoveFilletsFeature`.
extension CADIR.RemoveFilletsFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.RemoveFilletsFeature", fields: 3)
        try encoder.field("convexity", convexity)
        try encoder.field("maximumRadius", maximumRadius)
        try encoder.field("target", target)
    }
}

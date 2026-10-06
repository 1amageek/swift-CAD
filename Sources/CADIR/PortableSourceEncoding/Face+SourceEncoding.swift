import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Face`.
extension CADTopology.Face: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.Face", fields: 4)
        try encoder.field("id", id)
        try encoder.field("loops", loops)
        try encoder.field("orientation", orientation)
        try encoder.field("surfaceID", surfaceID)
    }
}

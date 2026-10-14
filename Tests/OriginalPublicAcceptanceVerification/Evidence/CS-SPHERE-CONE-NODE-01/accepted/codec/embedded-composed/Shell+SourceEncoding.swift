import CADCore
import CADTopology

/// Encodes original source fields owned by `CADTopology.Shell`.
extension CADTopology.Shell: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.Shell", fields: 3)
        try encoder.field("faceIDs", faceIDs)
        try encoder.field("id", id)
        try encoder.field("orientation", orientation)
    }
}

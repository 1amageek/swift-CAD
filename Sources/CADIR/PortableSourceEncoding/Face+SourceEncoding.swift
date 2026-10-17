import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Face`.
extension CADTopology.Face: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.Face", fields: 4, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("loops", loops, using: &admission)
        try encoder.field("orientation", orientation, using: &admission)
        try encoder.field("surfaceID", surfaceID, using: &admission)
    }
}

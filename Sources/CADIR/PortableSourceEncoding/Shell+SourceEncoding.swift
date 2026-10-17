import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Shell`.
extension CADTopology.Shell: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.Shell", fields: 3, using: &admission)
        try encoder.field("faceIDs", faceIDs, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("orientation", orientation, using: &admission)
    }
}

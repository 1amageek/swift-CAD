import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Loop`.
extension CADTopology.Loop: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADTopology.Loop", fields: 3)
        try encoder.field("coedges", coedges)
        try encoder.field("id", id)
        try encoder.field("role", role)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADTopology.Loop`.
extension CADTopology.Loop: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADTopology.Loop", fields: 3, using: &admission)
        try encoder.field("coedges", coedges, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("role", role, using: &admission)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SpatialPathKnot`.
extension CADIR.SpatialPathKnot: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SpatialPathKnot", fields: 5, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("incoming", incoming, using: &admission)
        try encoder.field("mode", mode, using: &admission)
        try encoder.field("outgoing", outgoing, using: &admission)
        try encoder.field("position", position, using: &admission)
    }
}

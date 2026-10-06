import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SpatialPathKnot`.
extension CADIR.SpatialPathKnot: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SpatialPathKnot", fields: 5)
        try encoder.field("id", id)
        try encoder.field("incoming", incoming)
        try encoder.field("mode", mode)
        try encoder.field("outgoing", outgoing)
        try encoder.field("position", position)
    }
}

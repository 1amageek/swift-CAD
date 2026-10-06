import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DirectMoveVector`.
extension CADIR.DirectMoveVector: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.DirectMoveVector", fields: 2)
        try encoder.field("direction", direction)
        try encoder.field("distance", distance)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepTwistKnot`.
extension CADIR.SweepTwistKnot: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SweepTwistKnot", fields: 2)
        try encoder.field("angle", angle)
        try encoder.field("position", position)
    }
}

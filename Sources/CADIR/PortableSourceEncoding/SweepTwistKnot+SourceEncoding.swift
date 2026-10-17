import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SweepTwistKnot`.
extension CADIR.SweepTwistKnot: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SweepTwistKnot", fields: 2, using: &admission)
        try encoder.field("angle", angle, using: &admission)
        try encoder.field("position", position, using: &admission)
    }
}

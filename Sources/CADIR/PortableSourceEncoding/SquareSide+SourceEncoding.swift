import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SquareSide`.
extension CADIR.SquareSide: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SquareSide", fields: 3, using: &admission)
        try encoder.field("continuity", continuity, using: &admission)
        try encoder.field("curve", curve, using: &admission)
        try encoder.field("isFree", isFree, using: &admission)
    }
}

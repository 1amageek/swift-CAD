import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SquareSide`.
extension CADIR.SquareSide: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SquareSide", fields: 3)
        try encoder.field("continuity", continuity)
        try encoder.field("curve", curve)
        try encoder.field("isFree", isFree)
    }
}

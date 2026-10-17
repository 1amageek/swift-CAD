import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.DirectMoveVector`.
extension CADIR.DirectMoveVector: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.DirectMoveVector", fields: 2, using: &admission)
        try encoder.field("direction", direction, using: &admission)
        try encoder.field("distance", distance, using: &admission)
    }
}

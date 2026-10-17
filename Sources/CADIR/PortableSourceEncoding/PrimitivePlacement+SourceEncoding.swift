import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PrimitivePlacement`.
extension CADIR.PrimitivePlacement: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.PrimitivePlacement", fields: 3, using: &admission)
        try encoder.field("axis", axis, using: &admission)
        try encoder.field("origin", origin, using: &admission)
        try encoder.field("referenceDirection", referenceDirection, using: &admission)
    }
}

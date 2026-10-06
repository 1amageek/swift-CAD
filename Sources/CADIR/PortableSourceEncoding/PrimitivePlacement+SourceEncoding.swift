import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PrimitivePlacement`.
extension CADIR.PrimitivePlacement: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.PrimitivePlacement", fields: 3)
        try encoder.field("axis", axis)
        try encoder.field("origin", origin)
        try encoder.field("referenceDirection", referenceDirection)
    }
}

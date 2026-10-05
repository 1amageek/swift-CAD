import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.AssemblyOccurrence`.
extension CADIR.AssemblyOccurrence: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.AssemblyOccurrence", fields: 4)
        try encoder.field("definitionID", definitionID)
        try encoder.field("id", id)
        try encoder.field("name", name)
        try encoder.field("placement", placement)
    }
}

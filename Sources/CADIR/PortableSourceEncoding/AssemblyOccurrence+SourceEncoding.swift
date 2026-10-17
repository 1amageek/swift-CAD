import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.AssemblyOccurrence`.
extension CADIR.AssemblyOccurrence: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.AssemblyOccurrence", fields: 4, using: &admission)
        try encoder.field("definitionID", definitionID, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("placement", placement, using: &admission)
    }
}

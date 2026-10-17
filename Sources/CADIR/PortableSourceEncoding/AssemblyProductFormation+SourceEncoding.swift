import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.AssemblyProductFormation`.
extension CADIR.AssemblyProductFormation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.AssemblyProductFormation", fields: 5, using: &admission)
        try encoder.field("description", description, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("productID", productID, using: &admission)
        try encoder.field("specifiedSource", specifiedSource, using: &admission)
        try encoder.field("versionIdentifier", versionIdentifier, using: &admission)
    }
}

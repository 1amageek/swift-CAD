import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.AssemblyProductFormation`.
extension CADIR.AssemblyProductFormation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.AssemblyProductFormation", fields: 5)
        try encoder.field("description", description)
        try encoder.field("id", id)
        try encoder.field("productID", productID)
        try encoder.field("specifiedSource", specifiedSource)
        try encoder.field("versionIdentifier", versionIdentifier)
    }
}

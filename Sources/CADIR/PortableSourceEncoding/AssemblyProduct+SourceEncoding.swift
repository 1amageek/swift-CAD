import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.AssemblyProduct`.
extension CADIR.AssemblyProduct: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.AssemblyProduct", fields: 4)
        try encoder.field("description", description)
        try encoder.field("id", id)
        try encoder.field("identifier", identifier)
        try encoder.field("name", name)
    }
}

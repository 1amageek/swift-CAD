import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PhysicalMaterialDescriptor`.
extension CADIR.PhysicalMaterialDescriptor: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.PhysicalMaterialDescriptor", fields: 4)
        try encoder.field("density", density)
        try encoder.field("description", description)
        try encoder.field("id", id)
        try encoder.field("name", name)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PhysicalMaterialDescriptor`.
extension CADIR.PhysicalMaterialDescriptor: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.PhysicalMaterialDescriptor", fields: 4, using: &admission)
        try encoder.field("density", density, using: &admission)
        try encoder.field("description", description, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("name", name, using: &admission)
    }
}

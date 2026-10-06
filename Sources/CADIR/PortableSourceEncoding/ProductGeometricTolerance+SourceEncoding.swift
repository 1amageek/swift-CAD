import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductGeometricTolerance`.
extension CADIR.ProductGeometricTolerance: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductGeometricTolerance", fields: 8)
        try encoder.field("datumIDs", datumIDs)
        try encoder.field("description", description)
        try encoder.field("id", id)
        try encoder.field("kind", kind)
        try encoder.field("magnitude", magnitude)
        try encoder.field("modifiers", modifiers)
        try encoder.field("name", name)
        try encoder.field("target", target)
    }
}

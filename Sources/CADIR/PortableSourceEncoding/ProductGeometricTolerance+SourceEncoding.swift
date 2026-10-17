import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductGeometricTolerance`.
extension CADIR.ProductGeometricTolerance: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductGeometricTolerance", fields: 8, using: &admission)
        try encoder.field("datumIDs", datumIDs, using: &admission)
        try encoder.field("description", description, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("kind", kind, using: &admission)
        try encoder.field("magnitude", magnitude, using: &admission)
        try encoder.field("modifiers", modifiers, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}

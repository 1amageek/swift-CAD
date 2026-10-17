import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeFrame`.
extension CADIR.IndependentShapeFrame: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeFrame", fields: 5, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("originalIGES", originalIGES, using: &admission)
        try encoder.field("originalSTEPPlacement", originalSTEPPlacement, using: &admission)
        try encoder.field("placement", placement, using: &admission)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeFrame`.
extension CADIR.IndependentShapeFrame: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeFrame", fields: 5)
        try encoder.field("id", id)
        try encoder.field("name", name)
        try encoder.field("originalIGES", originalIGES)
        try encoder.field("originalSTEPPlacement", originalSTEPPlacement)
        try encoder.field("placement", placement)
    }
}

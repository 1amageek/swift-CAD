import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.IndependentShapeInstance`.
extension CADIR.IndependentShapeInstance: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeInstance", fields: 7)
        try encoder.field("id", id)
        try encoder.field("name", name)
        try encoder.field("originalIGES", originalIGES)
        try encoder.field("originalSTEPPlacement", originalSTEPPlacement)
        try encoder.field("placement", placement)
        try encoder.field("placementName", placementName)
        try encoder.field("target", target)
    }
}

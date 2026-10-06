import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.AssemblyDefinition`.
extension CADIR.AssemblyDefinition: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.AssemblyDefinition", fields: 6)
        let orderedChildren = try encoder.canonicalOrder(children)
        try encoder.field("children", orderedChildren)
        try encoder.field("definitionDescription", definitionDescription)
        let orderedFeatures = try encoder.canonicalOrder(features)
        try encoder.field("features", orderedFeatures)
        try encoder.field("formationID", formationID)
        try encoder.field("id", id)
        try encoder.field("identifier", identifier)
    }
}

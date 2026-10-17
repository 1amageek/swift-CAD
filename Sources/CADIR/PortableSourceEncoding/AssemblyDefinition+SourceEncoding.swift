import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.AssemblyDefinition`.
extension CADIR.AssemblyDefinition: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.AssemblyDefinition", fields: 6, using: &admission)
        let orderedChildren = try encoder.canonicalOrder(children, using: &admission)
        try encoder.field("children", orderedChildren, using: &admission)
        try encoder.field("definitionDescription", definitionDescription, using: &admission)
        let orderedFeatures = try encoder.canonicalOrder(features, using: &admission)
        try encoder.field("features", orderedFeatures, using: &admission)
        try encoder.field("formationID", formationID, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("identifier", identifier, using: &admission)
    }
}

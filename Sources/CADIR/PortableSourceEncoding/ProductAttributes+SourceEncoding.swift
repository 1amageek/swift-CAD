import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAttributes`.
extension CADIR.ProductAttributes: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductAttributes", fields: 7)
        let orderedAssignments = try encoder.canonicalOrder(assignments)
        try encoder.field("assignments", orderedAssignments)
        let orderedItemCharacterizations = try encoder.canonicalOrder(itemCharacterizations)
        try encoder.field("itemCharacterizations", orderedItemCharacterizations)
        let orderedLayers = try encoder.canonicalOrder(layers)
        try encoder.field("layers", orderedLayers)
        try encoder.field("manufacturingInformation", manufacturingInformation)
        let orderedMaterials = try encoder.canonicalOrder(materials)
        try encoder.field("materials", orderedMaterials)
        let orderedShapeElementDescriptions = try encoder.canonicalOrder(shapeElementDescriptions)
        try encoder.field("shapeElementDescriptions", orderedShapeElementDescriptions)
        try encoder.field("viewMetadata", viewMetadata)
    }
}

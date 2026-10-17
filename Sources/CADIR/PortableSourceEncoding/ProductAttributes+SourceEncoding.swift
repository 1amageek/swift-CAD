import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAttributes`.
extension CADIR.ProductAttributes: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductAttributes", fields: 7, using: &admission)
        let orderedAssignments = try encoder.canonicalOrder(assignments, using: &admission)
        try encoder.field("assignments", orderedAssignments, using: &admission)
        let orderedItemCharacterizations = try encoder.canonicalOrder(itemCharacterizations, using: &admission)
        try encoder.field("itemCharacterizations", orderedItemCharacterizations, using: &admission)
        let orderedLayers = try encoder.canonicalOrder(layers, using: &admission)
        try encoder.field("layers", orderedLayers, using: &admission)
        try encoder.field("manufacturingInformation", manufacturingInformation, using: &admission)
        let orderedMaterials = try encoder.canonicalOrder(materials, using: &admission)
        try encoder.field("materials", orderedMaterials, using: &admission)
        let orderedShapeElementDescriptions = try encoder.canonicalOrder(shapeElementDescriptions, using: &admission)
        try encoder.field("shapeElementDescriptions", orderedShapeElementDescriptions, using: &admission)
        try encoder.field("viewMetadata", viewMetadata, using: &admission)
    }
}

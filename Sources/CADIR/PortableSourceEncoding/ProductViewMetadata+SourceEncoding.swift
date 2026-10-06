import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductViewMetadata`.
extension CADIR.ProductViewMetadata: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductViewMetadata", fields: 2)
        let orderedValidationProperties = try encoder.canonicalOrder(validationProperties)
        try encoder.field("validationProperties", orderedValidationProperties)
        let orderedViews = try encoder.canonicalOrder(views)
        try encoder.field("views", orderedViews)
    }
}

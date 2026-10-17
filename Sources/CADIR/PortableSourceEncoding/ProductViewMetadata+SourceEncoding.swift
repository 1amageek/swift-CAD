import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductViewMetadata`.
extension CADIR.ProductViewMetadata: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductViewMetadata", fields: 2, using: &admission)
        let orderedValidationProperties = try encoder.canonicalOrder(validationProperties, using: &admission)
        try encoder.field("validationProperties", orderedValidationProperties, using: &admission)
        let orderedViews = try encoder.canonicalOrder(views, using: &admission)
        try encoder.field("views", orderedViews, using: &admission)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductManufacturingInformation`.
extension CADIR.ProductManufacturingInformation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductManufacturingInformation", fields: 4, using: &admission)
        let orderedAnnotations = try encoder.canonicalOrder(annotations, using: &admission)
        try encoder.field("annotations", orderedAnnotations, using: &admission)
        let orderedDatums = try encoder.canonicalOrder(datums, using: &admission)
        try encoder.field("datums", orderedDatums, using: &admission)
        let orderedDimensions = try encoder.canonicalOrder(dimensions, using: &admission)
        try encoder.field("dimensions", orderedDimensions, using: &admission)
        let orderedTolerances = try encoder.canonicalOrder(tolerances, using: &admission)
        try encoder.field("tolerances", orderedTolerances, using: &admission)
    }
}

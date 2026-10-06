import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductManufacturingInformation`.
extension CADIR.ProductManufacturingInformation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductManufacturingInformation", fields: 4)
        let orderedAnnotations = try encoder.canonicalOrder(annotations)
        try encoder.field("annotations", orderedAnnotations)
        let orderedDatums = try encoder.canonicalOrder(datums)
        try encoder.field("datums", orderedDatums)
        let orderedDimensions = try encoder.canonicalOrder(dimensions)
        try encoder.field("dimensions", orderedDimensions)
        let orderedTolerances = try encoder.canonicalOrder(tolerances)
        try encoder.field("tolerances", orderedTolerances)
    }
}

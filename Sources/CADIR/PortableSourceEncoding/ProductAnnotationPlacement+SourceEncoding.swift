import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAnnotationPlacement`.
extension CADIR.ProductAnnotationPlacement: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductAnnotationPlacement", fields: 9)
        try encoder.field("annotationID", annotationID)
        try encoder.field("basisX", basisX)
        try encoder.field("direction", direction)
        try encoder.field("mappingDirection", mappingDirection)
        try encoder.field("mappingOrigin", mappingOrigin)
        try encoder.field("mappingUp", mappingUp)
        try encoder.field("origin", origin)
        try encoder.field("scale", scale)
        try encoder.field("up", up)
    }
}

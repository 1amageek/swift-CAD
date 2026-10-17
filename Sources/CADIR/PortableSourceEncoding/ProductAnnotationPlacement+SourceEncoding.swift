import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAnnotationPlacement`.
extension CADIR.ProductAnnotationPlacement: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductAnnotationPlacement", fields: 9, using: &admission)
        try encoder.field("annotationID", annotationID, using: &admission)
        try encoder.field("basisX", basisX, using: &admission)
        try encoder.field("direction", direction, using: &admission)
        try encoder.field("mappingDirection", mappingDirection, using: &admission)
        try encoder.field("mappingOrigin", mappingOrigin, using: &admission)
        try encoder.field("mappingUp", mappingUp, using: &admission)
        try encoder.field("origin", origin, using: &admission)
        try encoder.field("scale", scale, using: &admission)
        try encoder.field("up", up, using: &admission)
    }
}

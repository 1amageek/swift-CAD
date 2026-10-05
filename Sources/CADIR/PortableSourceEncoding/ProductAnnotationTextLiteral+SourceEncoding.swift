import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAnnotationTextLiteral`.
extension CADIR.ProductAnnotationTextLiteral: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductAnnotationTextLiteral", fields: 11)
        try encoder.field("alignment", alignment)
        try encoder.field("direction", direction)
        try encoder.field("fontName", fontName)
        try encoder.field("id", id)
        try encoder.field("literalName", literalName)
        try encoder.field("occurrenceName", occurrenceName)
        try encoder.field("origin", origin)
        try encoder.field("path", path)
        try encoder.field("placement", placement)
        try encoder.field("text", text)
        try encoder.field("up", up)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAnnotationTextLiteral`.
extension CADIR.ProductAnnotationTextLiteral: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductAnnotationTextLiteral", fields: 11, using: &admission)
        try encoder.field("alignment", alignment, using: &admission)
        try encoder.field("direction", direction, using: &admission)
        try encoder.field("fontName", fontName, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("literalName", literalName, using: &admission)
        try encoder.field("occurrenceName", occurrenceName, using: &admission)
        try encoder.field("origin", origin, using: &admission)
        try encoder.field("path", path, using: &admission)
        try encoder.field("placement", placement, using: &admission)
        try encoder.field("text", text, using: &admission)
        try encoder.field("up", up, using: &admission)
    }
}

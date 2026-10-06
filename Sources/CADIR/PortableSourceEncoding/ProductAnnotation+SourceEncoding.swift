import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAnnotation`.
extension CADIR.ProductAnnotation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ProductAnnotation", fields: 8)
        try encoder.field("id", id)
        try encoder.field("meaning", meaning)
        try encoder.field("name", name)
        try encoder.field("polylines", polylines)
        try encoder.field("semanticID", semanticID)
        try encoder.field("targets", targets)
        try encoder.field("text", text)
        try encoder.field("textLiterals", textLiterals)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ProductAnnotation`.
extension CADIR.ProductAnnotation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ProductAnnotation", fields: 8, using: &admission)
        try encoder.field("id", id, using: &admission)
        try encoder.field("meaning", meaning, using: &admission)
        try encoder.field("name", name, using: &admission)
        try encoder.field("polylines", polylines, using: &admission)
        try encoder.field("semanticID", semanticID, using: &admission)
        try encoder.field("targets", targets, using: &admission)
        try encoder.field("text", text, using: &admission)
        try encoder.field("textLiterals", textLiterals, using: &admission)
    }
}

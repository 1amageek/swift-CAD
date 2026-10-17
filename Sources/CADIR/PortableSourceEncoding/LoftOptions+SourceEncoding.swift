import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftOptions`.
extension CADIR.LoftOptions: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.LoftOptions", fields: 6, using: &admission)
        try encoder.field("closesSectionLoop", closesSectionLoop, using: &admission)
        try encoder.field("resultKind", resultKind, using: &admission)
        try encoder.field("sectionMatching", sectionMatching, using: &admission)
        try encoder.field("simplify", simplify, using: &admission)
        try encoder.field("smoothTangentScale", smoothTangentScale, using: &admission)
        try encoder.field("surfaceMode", surfaceMode, using: &admission)
    }
}

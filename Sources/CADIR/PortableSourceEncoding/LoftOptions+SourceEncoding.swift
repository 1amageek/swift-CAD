import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.LoftOptions`.
extension CADIR.LoftOptions: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.LoftOptions", fields: 6)
        try encoder.field("closesSectionLoop", closesSectionLoop)
        try encoder.field("resultKind", resultKind)
        try encoder.field("sectionMatching", sectionMatching)
        try encoder.field("simplify", simplify)
        try encoder.field("smoothTangentScale", smoothTangentScale)
        try encoder.field("surfaceMode", surfaceMode)
    }
}

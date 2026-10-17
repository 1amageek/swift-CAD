import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeOffsetFeature`.
extension CADIR.EdgeOffsetFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.EdgeOffsetFeature", fields: 6, using: &admission)
        try encoder.field("distance", distance, using: &admission)
        try encoder.field("edges", edges, using: &admission)
        try encoder.field("gapFill", gapFill, using: &admission)
        try encoder.field("isSymmetric", isSymmetric, using: &admission)
        try encoder.field("supportFaces", supportFaces, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}

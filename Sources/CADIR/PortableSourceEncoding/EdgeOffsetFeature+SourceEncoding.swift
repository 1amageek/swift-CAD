import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.EdgeOffsetFeature`.
extension CADIR.EdgeOffsetFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.EdgeOffsetFeature", fields: 6)
        try encoder.field("distance", distance)
        try encoder.field("edges", edges)
        try encoder.field("gapFill", gapFill)
        try encoder.field("isSymmetric", isSymmetric)
        try encoder.field("supportFaces", supportFaces)
        try encoder.field("target", target)
    }
}

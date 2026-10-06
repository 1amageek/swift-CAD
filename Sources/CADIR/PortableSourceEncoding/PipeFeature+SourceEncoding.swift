import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PipeFeature`.
extension CADIR.PipeFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.PipeFeature", fields: 14)
        try encoder.field("angle", angle)
        try encoder.field("approximationTolerance", approximationTolerance)
        try encoder.field("booleanOperation", booleanOperation)
        try encoder.field("diameter", diameter)
        try encoder.field("end", end)
        try encoder.field("endScale", endScale)
        try encoder.field("keepTools", keepTools)
        try encoder.field("path", path)
        try encoder.field("profile", profile)
        try encoder.field("start", start)
        try encoder.field("targets", targets)
        try encoder.field("thickness", thickness)
        try encoder.field("twist", twist)
        try encoder.field("vertexCount", vertexCount)
    }
}

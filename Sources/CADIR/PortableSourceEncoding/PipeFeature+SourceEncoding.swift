import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.PipeFeature`.
extension CADIR.PipeFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.PipeFeature", fields: 14, using: &admission)
        try encoder.field("angle", angle, using: &admission)
        try encoder.field("approximationTolerance", approximationTolerance, using: &admission)
        try encoder.field("booleanOperation", booleanOperation, using: &admission)
        try encoder.field("diameter", diameter, using: &admission)
        try encoder.field("end", end, using: &admission)
        try encoder.field("endScale", endScale, using: &admission)
        try encoder.field("keepTools", keepTools, using: &admission)
        try encoder.field("path", path, using: &admission)
        try encoder.field("profile", profile, using: &admission)
        try encoder.field("start", start, using: &admission)
        try encoder.field("targets", targets, using: &admission)
        try encoder.field("thickness", thickness, using: &admission)
        try encoder.field("twist", twist, using: &admission)
        try encoder.field("vertexCount", vertexCount, using: &admission)
    }
}

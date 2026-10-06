import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveMatchFeature`.
extension CADIR.CurveMatchFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveMatchFeature", fields: 6)
        try encoder.field("continuity", continuity)
        try encoder.field("source", source)
        try encoder.field("sourceEnd", sourceEnd)
        try encoder.field("target", target)
        try encoder.field("targetEnd", targetEnd)
        try encoder.field("targetOrientation", targetOrientation)
    }
}

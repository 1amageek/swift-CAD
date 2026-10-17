import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveMatchFeature`.
extension CADIR.CurveMatchFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveMatchFeature", fields: 6, using: &admission)
        try encoder.field("continuity", continuity, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("sourceEnd", sourceEnd, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("targetEnd", targetEnd, using: &admission)
        try encoder.field("targetOrientation", targetOrientation, using: &admission)
    }
}

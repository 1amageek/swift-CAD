import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceMatchFeature`.
extension CADIR.SurfaceMatchFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceMatchFeature", fields: 6, using: &admission)
        try encoder.field("continuity", continuity, using: &admission)
        try encoder.field("normalAlignment", normalAlignment, using: &admission)
        try encoder.field("source", source, using: &admission)
        try encoder.field("sourceParameter", sourceParameter, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("targetParameter", targetParameter, using: &admission)
    }
}

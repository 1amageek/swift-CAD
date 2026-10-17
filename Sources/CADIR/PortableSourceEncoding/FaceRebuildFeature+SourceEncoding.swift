import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceRebuildFeature`.
extension CADIR.FaceRebuildFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceRebuildFeature", fields: 6, using: &admission)
        try encoder.field("extendU", extendU, using: &admission)
        try encoder.field("extendV", extendV, using: &admission)
        try encoder.field("faces", faces, using: &admission)
        try encoder.field("method", method, using: &admission)
        try encoder.field("shrinks", shrinks, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}

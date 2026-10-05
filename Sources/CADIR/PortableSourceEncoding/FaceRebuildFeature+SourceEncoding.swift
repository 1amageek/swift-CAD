import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceRebuildFeature`.
extension CADIR.FaceRebuildFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceRebuildFeature", fields: 6)
        try encoder.field("extendU", extendU)
        try encoder.field("extendV", extendV)
        try encoder.field("faces", faces)
        try encoder.field("method", method)
        try encoder.field("shrinks", shrinks)
        try encoder.field("target", target)
    }
}

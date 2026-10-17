import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceDeleteFeature`.
extension CADIR.FaceDeleteFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceDeleteFeature", fields: 3, using: &admission)
        try encoder.field("faces", faces, using: &admission)
        try encoder.field("heals", heals, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}

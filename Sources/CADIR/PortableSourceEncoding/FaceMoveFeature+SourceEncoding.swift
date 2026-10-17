import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceMoveFeature`.
extension CADIR.FaceMoveFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceMoveFeature", fields: 3, using: &admission)
        try encoder.field("face", face, using: &admission)
        try encoder.field("target", target, using: &admission)
        try encoder.field("translation", translation, using: &admission)
    }
}

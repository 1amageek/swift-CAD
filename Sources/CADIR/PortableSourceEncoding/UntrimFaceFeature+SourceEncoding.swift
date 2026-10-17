import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.UntrimFaceFeature`.
extension CADIR.UntrimFaceFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.UntrimFaceFeature", fields: 3, using: &admission)
        try encoder.field("face", face, using: &admission)
        try encoder.field("keepsEdges", keepsEdges, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}

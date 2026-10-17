import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.MirrorFeature`.
extension CADIR.MirrorFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.MirrorFeature", fields: 5, using: &admission)
        try encoder.field("cutsAtPlane", cutsAtPlane, using: &admission)
        try encoder.field("output", output, using: &admission)
        try encoder.field("planeNormal", planeNormal, using: &admission)
        try encoder.field("planeOrigin", planeOrigin, using: &admission)
        try encoder.field("target", target, using: &admission)
    }
}

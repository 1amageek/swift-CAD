import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.MirrorFeature`.
extension CADIR.MirrorFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.MirrorFeature", fields: 5)
        try encoder.field("cutsAtPlane", cutsAtPlane)
        try encoder.field("output", output)
        try encoder.field("planeNormal", planeNormal)
        try encoder.field("planeOrigin", planeOrigin)
        try encoder.field("target", target)
    }
}

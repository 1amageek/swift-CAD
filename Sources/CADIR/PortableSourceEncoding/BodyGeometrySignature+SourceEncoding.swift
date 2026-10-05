import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.BodyGeometrySignature`.
extension CADIR.BodyGeometrySignature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.BodyGeometrySignature", fields: 2)
        try encoder.field("kind", kind)
        try encoder.field("shells", shells)
    }
}

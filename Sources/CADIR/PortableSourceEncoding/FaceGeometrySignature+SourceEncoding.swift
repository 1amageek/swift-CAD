import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceGeometrySignature`.
extension CADIR.FaceGeometrySignature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceGeometrySignature", fields: 3)
        try encoder.field("loops", loops)
        try encoder.field("orientation", orientation)
        try encoder.field("surface", surface)
    }
}

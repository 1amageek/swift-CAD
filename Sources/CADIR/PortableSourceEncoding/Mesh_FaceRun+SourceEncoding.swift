import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.Mesh.FaceRun`.
extension CADIR.Mesh.FaceRun: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.Mesh.FaceRun", fields: 2)
        try encoder.field("faceID", faceID)
        try encoder.field("triangleCount", triangleCount)
    }
}

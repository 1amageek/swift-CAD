import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.Mesh.FaceRun`.
extension CADIR.Mesh.FaceRun: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.Mesh.FaceRun", fields: 2, using: &admission)
        try encoder.field("faceID", faceID, using: &admission)
        try encoder.field("triangleCount", triangleCount, using: &admission)
    }
}

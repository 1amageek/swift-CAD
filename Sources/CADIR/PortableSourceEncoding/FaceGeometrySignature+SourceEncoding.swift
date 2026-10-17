import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceGeometrySignature`.
extension CADIR.FaceGeometrySignature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceGeometrySignature", fields: 3, using: &admission)
        try encoder.field("loops", loops, using: &admission)
        try encoder.field("orientation", orientation, using: &admission)
        try encoder.field("surface", surface, using: &admission)
    }
}

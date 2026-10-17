import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceDeleteTargetReference`.
extension CADIR.FaceDeleteTargetReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceDeleteTargetReference", fields: 1, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
    }
}

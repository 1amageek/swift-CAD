import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceDeleteTargetReference`.
extension CADIR.FaceDeleteTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceDeleteTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}

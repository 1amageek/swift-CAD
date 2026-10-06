import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceOffsetTargetReference`.
extension CADIR.FaceOffsetTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceOffsetTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}

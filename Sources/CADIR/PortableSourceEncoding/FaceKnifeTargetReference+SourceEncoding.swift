import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceKnifeTargetReference`.
extension CADIR.FaceKnifeTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceKnifeTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}

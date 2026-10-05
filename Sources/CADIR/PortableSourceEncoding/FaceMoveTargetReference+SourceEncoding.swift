import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceMoveTargetReference`.
extension CADIR.FaceMoveTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceMoveTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceDraftTargetReference`.
extension CADIR.FaceDraftTargetReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceDraftTargetReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}

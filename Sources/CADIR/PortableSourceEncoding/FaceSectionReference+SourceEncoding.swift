import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceSectionReference`.
extension CADIR.FaceSectionReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.FaceSectionReference", fields: 3)
        try encoder.field("bodyRole", bodyRole)
        try encoder.field("face", face)
        try encoder.field("featureID", featureID)
    }
}

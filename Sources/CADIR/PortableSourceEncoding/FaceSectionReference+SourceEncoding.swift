import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.FaceSectionReference`.
extension CADIR.FaceSectionReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.FaceSectionReference", fields: 3, using: &admission)
        try encoder.field("bodyRole", bodyRole, using: &admission)
        try encoder.field("face", face, using: &admission)
        try encoder.field("featureID", featureID, using: &admission)
    }
}

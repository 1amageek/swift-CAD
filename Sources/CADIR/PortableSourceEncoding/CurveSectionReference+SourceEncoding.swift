import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveSectionReference`.
extension CADIR.CurveSectionReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveSectionReference", fields: 3)
        try encoder.field("featureID", featureID)
        try encoder.field("isReversed", isReversed)
        try encoder.field("parameterDomain", parameterDomain)
    }
}

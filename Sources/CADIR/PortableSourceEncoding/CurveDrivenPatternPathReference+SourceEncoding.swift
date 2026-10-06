import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveDrivenPatternPathReference`.
extension CADIR.CurveDrivenPatternPathReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveDrivenPatternPathReference", fields: 1)
        try encoder.field("featureID", featureID)
    }
}

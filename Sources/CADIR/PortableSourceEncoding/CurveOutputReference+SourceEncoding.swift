import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveOutputReference`.
extension CADIR.CurveOutputReference: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveOutputReference", fields: 2)
        try encoder.field("curveIndex", curveIndex)
        try encoder.field("featureID", featureID)
    }
}

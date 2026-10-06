import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalBSplineCurve2DContinuation`.
extension CADGeometry.OriginalBSplineCurve2DContinuation: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalBSplineCurve2DContinuation", fields: 4)
        try encoder.field("certificationTolerance", certificationTolerance)
        try encoder.field("endParameter", endParameter)
        try encoder.field("original", original)
        try encoder.field("startParameter", startParameter)
    }
}

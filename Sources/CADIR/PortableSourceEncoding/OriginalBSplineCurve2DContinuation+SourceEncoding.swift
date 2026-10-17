import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OriginalBSplineCurve2DContinuation`.
extension CADGeometry.OriginalBSplineCurve2DContinuation: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalBSplineCurve2DContinuation", fields: 4, using: &admission)
        try encoder.field("certificationTolerance", certificationTolerance, using: &admission)
        try encoder.field("endParameter", endParameter, using: &admission)
        try encoder.field("original", original, using: &admission)
        try encoder.field("startParameter", startParameter, using: &admission)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.BSplineCurve2D`.
extension CADGeometry.BSplineCurve2D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.BSplineCurve2D", fields: 4, using: &admission)
        try encoder.field("controlPoints", controlPoints, using: &admission)
        try encoder.field("degree", degree, using: &admission)
        try encoder.field("knots", knots, using: &admission)
        try encoder.field("weights", weights, using: &admission)
    }
}

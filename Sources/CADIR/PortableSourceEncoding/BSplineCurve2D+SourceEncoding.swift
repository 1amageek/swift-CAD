import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.BSplineCurve2D`.
extension CADGeometry.BSplineCurve2D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.BSplineCurve2D", fields: 4)
        try encoder.field("controlPoints", controlPoints)
        try encoder.field("degree", degree)
        try encoder.field("knots", knots)
        try encoder.field("weights", weights)
    }
}

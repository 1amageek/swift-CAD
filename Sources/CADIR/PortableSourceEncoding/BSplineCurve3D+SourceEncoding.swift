import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.BSplineCurve3D`.
extension CADGeometry.BSplineCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.BSplineCurve3D", fields: 6)
        try encoder.field("controlPoints", controlPoints)
        try encoder.field("degree", degree)
        try encoder.field("isPeriodic", isPeriodic)
        try encoder.field("knots", knots)
        try encoder.field("periodicOrigin", periodicOrigin)
        try encoder.field("weights", weights)
    }
}

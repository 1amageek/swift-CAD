import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.BSplineSurface3D`.
extension CADGeometry.BSplineSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.BSplineSurface3D", fields: 10)
        try encoder.field("controlPoints", controlPoints)
        try encoder.field("isUPeriodic", isUPeriodic)
        try encoder.field("isVPeriodic", isVPeriodic)
        try encoder.field("uDegree", uDegree)
        try encoder.field("uKnots", uKnots)
        try encoder.field("uPeriodicOrigin", uPeriodicOrigin)
        try encoder.field("vDegree", vDegree)
        try encoder.field("vKnots", vKnots)
        try encoder.field("vPeriodicOrigin", vPeriodicOrigin)
        try encoder.field("weights", weights)
    }
}

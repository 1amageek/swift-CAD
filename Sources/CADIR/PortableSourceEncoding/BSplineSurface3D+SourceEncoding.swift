import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.BSplineSurface3D`.
extension CADGeometry.BSplineSurface3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.BSplineSurface3D", fields: 10, using: &admission)
        try encoder.field("controlPoints", controlPoints, using: &admission)
        try encoder.field("isUPeriodic", isUPeriodic, using: &admission)
        try encoder.field("isVPeriodic", isVPeriodic, using: &admission)
        try encoder.field("uDegree", uDegree, using: &admission)
        try encoder.field("uKnots", uKnots, using: &admission)
        try encoder.field("uPeriodicOrigin", uPeriodicOrigin, using: &admission)
        try encoder.field("vDegree", vDegree, using: &admission)
        try encoder.field("vKnots", vKnots, using: &admission)
        try encoder.field("vPeriodicOrigin", vPeriodicOrigin, using: &admission)
        try encoder.field("weights", weights, using: &admission)
    }
}

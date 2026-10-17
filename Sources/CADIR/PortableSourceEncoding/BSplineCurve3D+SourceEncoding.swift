import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.BSplineCurve3D`.
extension CADGeometry.BSplineCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.BSplineCurve3D", fields: 6, using: &admission)
        try encoder.field("controlPoints", controlPoints, using: &admission)
        try encoder.field("degree", degree, using: &admission)
        try encoder.field("isPeriodic", isPeriodic, using: &admission)
        try encoder.field("knots", knots, using: &admission)
        try encoder.field("periodicOrigin", periodicOrigin, using: &admission)
        try encoder.field("weights", weights, using: &admission)
    }
}

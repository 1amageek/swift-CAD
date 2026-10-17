import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveContinuityTolerances`.
extension CADIR.CurveContinuityTolerances: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CurveContinuityTolerances", fields: 3, using: &admission)
        try encoder.field("curvatureVector", curvatureVector, using: &admission)
        try encoder.field("positionDistance", positionDistance, using: &admission)
        try encoder.field("tangentAngle", tangentAngle, using: &admission)
    }
}

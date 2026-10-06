import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CurveContinuityTolerances`.
extension CADIR.CurveContinuityTolerances: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CurveContinuityTolerances", fields: 3)
        try encoder.field("curvatureVector", curvatureVector)
        try encoder.field("positionDistance", positionDistance)
        try encoder.field("tangentAngle", tangentAngle)
    }
}

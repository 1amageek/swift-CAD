import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchSplineLineTangencyConstraint`.
extension CADIR.SketchSplineLineTangencyConstraint: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SketchSplineLineTangencyConstraint", fields: 3, using: &admission)
        try encoder.field("line", line, using: &admission)
        try encoder.field("orientation", orientation, using: &admission)
        try encoder.field("splineEndpoint", splineEndpoint, using: &admission)
    }
}

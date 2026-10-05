import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchSplineLineTangencyConstraint`.
extension CADIR.SketchSplineLineTangencyConstraint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SketchSplineLineTangencyConstraint", fields: 3)
        try encoder.field("line", line)
        try encoder.field("orientation", orientation)
        try encoder.field("splineEndpoint", splineEndpoint)
    }
}

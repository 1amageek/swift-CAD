import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SketchSplineEndpointTangencyConstraint`.
extension CADIR.SketchSplineEndpointTangencyConstraint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SketchSplineEndpointTangencyConstraint", fields: 3)
        try encoder.field("first", first)
        try encoder.field("orientation", orientation)
        try encoder.field("second", second)
    }
}

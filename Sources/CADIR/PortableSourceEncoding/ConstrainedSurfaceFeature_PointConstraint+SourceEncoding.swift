import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ConstrainedSurfaceFeature.PointConstraint`.
extension CADIR.ConstrainedSurfaceFeature.PointConstraint: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ConstrainedSurfaceFeature.PointConstraint", fields: 1)
        try encoder.field("position", position)
    }
}

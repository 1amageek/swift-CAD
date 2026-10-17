import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ConstrainedSurfaceFeature.PointConstraint`.
extension CADIR.ConstrainedSurfaceFeature.PointConstraint: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ConstrainedSurfaceFeature.PointConstraint", fields: 1, using: &admission)
        try encoder.field("position", position, using: &admission)
    }
}

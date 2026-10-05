import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ConstrainedSurfaceFeature`.
extension CADIR.ConstrainedSurfaceFeature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.ConstrainedSurfaceFeature", fields: 4)
        try encoder.field("angularTolerance", angularTolerance)
        try encoder.field("optimization", optimization)
        try encoder.field("points", points)
        try encoder.field("positionTolerance", positionTolerance)
    }
}

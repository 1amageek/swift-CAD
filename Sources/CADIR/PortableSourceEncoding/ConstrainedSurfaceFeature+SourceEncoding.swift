import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.ConstrainedSurfaceFeature`.
extension CADIR.ConstrainedSurfaceFeature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.ConstrainedSurfaceFeature", fields: 4, using: &admission)
        try encoder.field("angularTolerance", angularTolerance, using: &admission)
        try encoder.field("optimization", optimization, using: &admission)
        try encoder.field("points", points, using: &admission)
        try encoder.field("positionTolerance", positionTolerance, using: &admission)
    }
}

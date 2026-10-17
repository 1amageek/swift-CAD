import CADCore
import CADGeometry

/// Encodes the immutable authored polyline authority, excluding reconstruction policy.
extension CADGeometry.OriginalPolylineCurve3D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OriginalPolylineCurve3D", fields: 2, using: &admission)
        try encoder.field("isClosed", isClosed, using: &admission)
        try encoder.field("points", points, using: &admission)
    }
}

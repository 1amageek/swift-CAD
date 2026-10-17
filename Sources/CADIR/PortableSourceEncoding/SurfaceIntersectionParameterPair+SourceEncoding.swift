import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.SurfaceIntersectionParameterPair`.
extension CADGeometry.SurfaceIntersectionParameterPair: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.SurfaceIntersectionParameterPair", fields: 2, using: &admission)
        try encoder.field("first", first, using: &admission)
        try encoder.field("second", second, using: &admission)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.SurfaceParameter`.
extension CADGeometry.SurfaceParameter: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.SurfaceParameter", fields: 2, using: &admission)
        try encoder.field("u", u, using: &admission)
        try encoder.field("v", v, using: &admission)
    }
}

import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceParameterReference`.
extension CADIR.SurfaceParameterReference: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceParameterReference", fields: 3, using: &admission)
        try encoder.field("surface", surface, using: &admission)
        try encoder.field("u", u, using: &admission)
        try encoder.field("v", v, using: &admission)
    }
}

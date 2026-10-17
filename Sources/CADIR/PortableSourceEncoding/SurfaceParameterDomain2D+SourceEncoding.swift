import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceParameterDomain2D`.
extension CADIR.SurfaceParameterDomain2D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.SurfaceParameterDomain2D", fields: 4, using: &admission)
        try encoder.field("uLowerBound", uLowerBound, using: &admission)
        try encoder.field("uUpperBound", uUpperBound, using: &admission)
        try encoder.field("vLowerBound", vLowerBound, using: &admission)
        try encoder.field("vUpperBound", vUpperBound, using: &admission)
    }
}

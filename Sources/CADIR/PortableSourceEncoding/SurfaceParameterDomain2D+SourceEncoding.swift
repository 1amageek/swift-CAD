import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.SurfaceParameterDomain2D`.
extension CADIR.SurfaceParameterDomain2D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.SurfaceParameterDomain2D", fields: 4)
        try encoder.field("uLowerBound", uLowerBound)
        try encoder.field("uUpperBound", uUpperBound)
        try encoder.field("vLowerBound", vLowerBound)
        try encoder.field("vUpperBound", vUpperBound)
    }
}

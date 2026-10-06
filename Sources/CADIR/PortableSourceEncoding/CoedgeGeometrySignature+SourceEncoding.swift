import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CoedgeGeometrySignature`.
extension CADIR.CoedgeGeometrySignature: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.CoedgeGeometrySignature", fields: 3)
        try encoder.field("edge", edge)
        try encoder.field("orientation", orientation)
        try encoder.field("surfaceParameterCurve", surfaceParameterCurve)
    }
}

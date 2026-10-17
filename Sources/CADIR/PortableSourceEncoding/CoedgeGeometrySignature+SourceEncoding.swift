import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADIR.CoedgeGeometrySignature`.
extension CADIR.CoedgeGeometrySignature: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.CoedgeGeometrySignature", fields: 3, using: &admission)
        try encoder.field("edge", edge, using: &admission)
        try encoder.field("orientation", orientation, using: &admission)
        try encoder.field("surfaceParameterCurve", surfaceParameterCurve, using: &admission)
    }
}

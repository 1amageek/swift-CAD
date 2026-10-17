import CADCore
import CADGeometry
import CADTopology

/// Encodes original source fields owned by `CADGeometry.OffsetSurfaceParameterCurveImage`.
extension CADGeometry.OffsetSurfaceParameterCurveImage: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADGeometry.OffsetSurfaceParameterCurveImage", fields: 3, using: &admission)
        try encoder.field("isPullback", isPullback, using: &admission)
        try encoder.field("offset", offset, using: &admission)
        try encoder.field("source", source, using: &admission)
    }
}

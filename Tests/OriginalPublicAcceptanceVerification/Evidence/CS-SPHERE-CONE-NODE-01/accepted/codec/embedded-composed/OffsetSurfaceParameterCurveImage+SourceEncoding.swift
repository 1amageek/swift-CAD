import CADCore

/// Encodes original source fields owned by `CADGeometry.OffsetSurfaceParameterCurveImage`.
extension CADGeometry.OffsetSurfaceParameterCurveImage: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OffsetSurfaceParameterCurveImage", fields: 3)
        try encoder.field("isPullback", isPullback)
        try encoder.field("offset", offset)
        try encoder.field("source", source)
    }
}

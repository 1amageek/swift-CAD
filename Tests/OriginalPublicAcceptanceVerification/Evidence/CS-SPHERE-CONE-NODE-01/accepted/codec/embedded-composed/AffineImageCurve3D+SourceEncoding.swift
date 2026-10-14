import CADCore

/// Encodes original source fields owned by `CADGeometry.AffineImageCurve3D`.
extension CADGeometry.AffineImageCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.AffineImageCurve3D", fields: 2)
        try encoder.field("source", source)
        try encoder.field("transform", transform)
    }
}

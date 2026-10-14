import CADCore

/// Encodes original source fields owned by `CADGeometry.RigidImageCurve3D`.
extension CADGeometry.RigidImageCurve3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.RigidImageCurve3D", fields: 2)
        try encoder.field("source", source)
        try encoder.field("transform", transform)
    }
}

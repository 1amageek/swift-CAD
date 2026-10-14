import CADCore

/// Encodes original source fields owned by `CADGeometry.RigidImageSurfaceParameterCurve`.
extension CADGeometry.RigidImageSurfaceParameterCurve: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.RigidImageSurfaceParameterCurve", fields: 5)
        try encoder.field("endFraction", endFraction)
        try encoder.field("source", source)
        try encoder.field("startFraction", startFraction)
        try encoder.field("targetSurface", targetSurface)
        try encoder.field("transform", transform)
    }
}

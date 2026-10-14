import CADCore

/// Encodes original source fields owned by `CADGeometry.OriginalRevolutionSurface3D`.
extension CADGeometry.OriginalRevolutionSurface3D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalRevolutionSurface3D", fields: 4)
        try encoder.field("axisDirection", axisDirection)
        try encoder.field("axisOrigin", axisOrigin)
        try encoder.field("generator", generator)
        try encoder.field("uDomain", uDomain)
    }
}

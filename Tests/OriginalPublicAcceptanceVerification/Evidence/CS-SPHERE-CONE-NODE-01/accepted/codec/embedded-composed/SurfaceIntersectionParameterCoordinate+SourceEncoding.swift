import CADCore

/// Encodes original source fields owned by `CADGeometry.SurfaceIntersectionParameterCoordinate`.
extension CADGeometry.SurfaceIntersectionParameterCoordinate: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.SurfaceIntersectionParameterCoordinate", caseName: "raw", values: 1)
        try encoder.field("rawValue", rawValue)
    }
}

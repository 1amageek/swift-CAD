import CADCore

/// Encodes original source fields owned by `CADGeometry.SurfaceParameterDirection`.
extension CADGeometry.SurfaceParameterDirection: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.SurfaceParameterDirection", caseName: rawValue, values: 0)
    }
}

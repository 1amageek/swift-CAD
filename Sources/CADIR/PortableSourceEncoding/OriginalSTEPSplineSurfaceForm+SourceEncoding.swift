import CADCore

/// Preserves the original surface form assertion without inferring it from geometry.
extension OriginalSTEPSplineSurfaceForm: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.OriginalSTEPSplineSurfaceForm", caseName: rawValue, values: 0)
    }
}

import CADCore

/// Preserves the original surface form assertion without inferring it from geometry.
extension OriginalSTEPSplineSurfaceForm: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.OriginalSTEPSplineSurfaceForm", caseName: rawValue, values: 0, using: &admission)
    }
}

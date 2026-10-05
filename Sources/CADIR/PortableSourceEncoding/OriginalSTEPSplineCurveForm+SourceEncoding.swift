import CADCore

/// Preserves the original curve form assertion without inferring it from geometry.
extension OriginalSTEPSplineCurveForm: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.OriginalSTEPSplineCurveForm", caseName: rawValue, values: 0)
    }
}

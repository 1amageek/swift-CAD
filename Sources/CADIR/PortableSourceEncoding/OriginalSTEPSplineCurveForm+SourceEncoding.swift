import CADCore

/// Preserves the original curve form assertion without inferring it from geometry.
extension OriginalSTEPSplineCurveForm: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.OriginalSTEPSplineCurveForm", caseName: rawValue, values: 0, using: &admission)
    }
}

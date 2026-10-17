import CADCore

/// Preserves the authored standard knot specification.
extension OriginalSTEPSplineKnotSpecification: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.OriginalSTEPSplineKnotSpecification", caseName: rawValue, values: 0, using: &admission)
    }
}

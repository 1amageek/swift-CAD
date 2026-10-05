import CADCore

/// Preserves the authored standard knot specification.
extension OriginalSTEPSplineKnotSpecification: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.OriginalSTEPSplineKnotSpecification", caseName: rawValue, values: 0)
    }
}

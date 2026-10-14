import CADCore

extension OriginalCurveConstructionParameterLaw: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADGeometry.OriginalCurveConstructionParameterLaw", caseName: rawValue, values: 0)
    }
}

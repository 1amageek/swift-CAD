import CADCore

/// Preserves the authored true, false or unknown standard assertion.
extension OriginalSTEPLogical: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADIR.OriginalSTEPLogical", caseName: rawValue, values: 0)
    }
}

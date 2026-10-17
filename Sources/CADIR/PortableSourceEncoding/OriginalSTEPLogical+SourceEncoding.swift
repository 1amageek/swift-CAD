import CADCore

/// Preserves the authored true, false or unknown standard assertion.
extension OriginalSTEPLogical: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADIR.OriginalSTEPLogical", caseName: rawValue, values: 0, using: &admission)
    }
}

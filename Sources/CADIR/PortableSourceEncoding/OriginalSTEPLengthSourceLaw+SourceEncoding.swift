import CADCore

/// Retains original metre prefix or complete original conversion chain.
extension OriginalSTEPLengthSource.Law: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .metre(let prefix):
            try encoder.enumeration("CADIR.OriginalSTEPLengthSource.Law", caseName: "metre", values: 1)
            try encoder.field("prefix", prefix)
        case .conversion(let value):
            try encoder.enumeration("CADIR.OriginalSTEPLengthSource.Law", caseName: "conversion", values: 1)
            try encoder.field("_0", value)
        }
    }
}

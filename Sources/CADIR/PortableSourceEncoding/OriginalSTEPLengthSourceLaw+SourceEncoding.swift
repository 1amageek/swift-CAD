import CADCore

/// Retains original metre prefix or complete original conversion chain.
extension OriginalSTEPLengthSource.Law: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .metre(let prefix):
            try encoder.enumeration("CADIR.OriginalSTEPLengthSource.Law", caseName: "metre", values: 1, using: &admission)
            try encoder.field("prefix", prefix, using: &admission)
        case .conversion(let value):
            try encoder.enumeration("CADIR.OriginalSTEPLengthSource.Law", caseName: "conversion", values: 1, using: &admission)
            try encoder.field("_0", value, using: &admission)
        }
    }
}

import CADCore

/// Encodes the complete original IGES lexical source and authored adjustments.
extension OriginalIGESMatrixSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.OriginalIGESMatrixSource", fields: 4, using: &admission)
        try encoder.field("adjustments", adjustments, using: &admission)
        try encoder.field("coefficients", coefficients, using: &admission)
        try encoder.field("form", form, using: &admission)
        try encoder.field("lengthUnit", lengthUnit, using: &admission)
    }
}

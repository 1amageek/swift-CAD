import CADCore

/// Encodes the complete original IGES lexical source and authored adjustments.
extension OriginalIGESMatrixSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalIGESMatrixSource", fields: 4)
        try encoder.field("adjustments", adjustments)
        try encoder.field("coefficients", coefficients)
        try encoder.field("form", form)
        try encoder.field("lengthUnit", lengthUnit)
    }
}

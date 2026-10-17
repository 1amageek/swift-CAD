import CADCore

/// Encodes the complete original IGES lexical source and authored adjustments.
extension OriginalIGESInstanceSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.OriginalIGESInstanceSource", fields: 5, using: &admission)
        try encoder.field("adjustments", adjustments, using: &admission)
        try encoder.field("lengthUnit", lengthUnit, using: &admission)
        try encoder.field("matrixFrameID", matrixFrameID, using: &admission)
        try encoder.field("scale", scale, using: &admission)
        try encoder.field("translation", translation, using: &admission)
    }
}

import CADCore

/// Encodes the complete original IGES lexical source and authored adjustments.
extension OriginalIGESInstanceSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.OriginalIGESInstanceSource", fields: 5)
        try encoder.field("adjustments", adjustments)
        try encoder.field("lengthUnit", lengthUnit)
        try encoder.field("matrixFrameID", matrixFrameID)
        try encoder.field("scale", scale)
        try encoder.field("translation", translation)
    }
}

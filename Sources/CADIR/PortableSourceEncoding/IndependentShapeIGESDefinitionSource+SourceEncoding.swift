import CADCore

/// Encodes the original IGES directory label and forward defining frame.
extension IndependentShapeIGESDefinitionSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADIR.IndependentShapeIGESDefinitionSource", fields: 3)
        try encoder.field("adjustments", adjustments)
        try encoder.field("definingFrameID", definingFrameID)
        try encoder.field("directoryLabel", directoryLabel)
    }
}

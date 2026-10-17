import CADCore

/// Encodes the original IGES directory label and forward defining frame.
extension IndependentShapeIGESDefinitionSource: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADIR.IndependentShapeIGESDefinitionSource", fields: 3, using: &admission)
        try encoder.field("adjustments", adjustments, using: &admission)
        try encoder.field("definingFrameID", definingFrameID, using: &admission)
        try encoder.field("directoryLabel", directoryLabel, using: &admission)
    }
}

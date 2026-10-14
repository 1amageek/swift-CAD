import CADCore

/// Encodes original source fields; prepared geometry remains derived.
extension OriginalNormalizedAffineSource: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.OriginalNormalizedAffineSource", fields: 9)
        try encoder.field("adjustments", adjustments)
        try encoder.field("axis1", axis1)
        try encoder.field("axis2", axis2)
        try encoder.field("axis3", axis3)
        try encoder.field("family", family)
        try encoder.field("lengthGain", lengthGain)
        try encoder.field("linearGain", linearGain)
        try encoder.field("location", location)
        try encoder.field("scale", scale)
    }
}

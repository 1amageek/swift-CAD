/// Encodes original source fields owned by `CADCore.ModelingTolerance`.
extension CADCore.ModelingTolerance: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADCore.ModelingTolerance", fields: 3)
        try encoder.field("angle", angle)
        try encoder.field("distance", distance)
        try encoder.field("relative", relative)
    }
}

/// Encodes original source fields owned by `CADCore.Point2D`.
extension CADCore.Point2D: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADCore.Point2D", fields: 2)
        try encoder.field("x", x)
        try encoder.field("y", y)
    }
}

/// Encodes original source fields owned by `CADCore.Point2D`.
extension CADCore.Point2D: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADCore.Point2D", fields: 2, using: &admission)
        try encoder.field("x", x, using: &admission)
        try encoder.field("y", y, using: &admission)
    }
}

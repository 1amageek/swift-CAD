/// Encodes original source fields owned by `CADCore.UnitSystem`.
extension CADCore.UnitSystem: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADCore.UnitSystem", fields: 2, using: &admission)
        try encoder.field("angle", angle, using: &admission)
        try encoder.field("length", length, using: &admission)
    }
}

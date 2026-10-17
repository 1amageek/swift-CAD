/// Encodes original source fields owned by `CADCore.ModelingTolerance`.
extension CADCore.ModelingTolerance: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.record("CADCore.ModelingTolerance", fields: 3, using: &admission)
        try encoder.field("angle", angle, using: &admission)
        try encoder.field("distance", distance, using: &admission)
        try encoder.field("relative", relative, using: &admission)
    }
}

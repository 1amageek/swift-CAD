/// Encodes original source fields owned by `CADCore.AngleUnit`.
extension CADCore.AngleUnit: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.enumeration("CADCore.AngleUnit", caseName: rawValue, values: 0, using: &admission)
    }
}

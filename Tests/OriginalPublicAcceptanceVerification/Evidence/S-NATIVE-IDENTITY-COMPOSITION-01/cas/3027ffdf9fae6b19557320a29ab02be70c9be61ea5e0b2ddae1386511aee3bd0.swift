/// Encodes original source fields owned by `CADCore.AngleUnit`.
extension CADCore.AngleUnit: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADCore.AngleUnit", caseName: rawValue, values: 0)
    }
}

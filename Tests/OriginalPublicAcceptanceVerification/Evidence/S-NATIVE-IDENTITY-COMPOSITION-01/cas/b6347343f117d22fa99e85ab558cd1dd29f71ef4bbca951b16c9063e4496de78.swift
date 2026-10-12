/// Encodes original source fields owned by `CADCore.LengthUnit`.
extension CADCore.LengthUnit: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADCore.LengthUnit", caseName: rawValue, values: 0)
    }
}

/// Encodes original source fields owned by `CADCore.QuantityKind`.
extension CADCore.QuantityKind: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.enumeration("CADCore.QuantityKind", caseName: rawValue, values: 0)
    }
}

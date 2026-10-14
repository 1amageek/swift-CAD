import CADCore

/// Encodes original source fields owned by `CADGeometry.ScalarInterval`.
extension CADGeometry.ScalarInterval: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.record("CADGeometry.ScalarInterval", fields: 2)
        try encoder.field("lower", lower)
        try encoder.field("upper", upper)
    }
}

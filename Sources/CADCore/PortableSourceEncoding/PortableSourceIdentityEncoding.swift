extension PortableIdentity128: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.tag(0x12); try encoder.word(high); try encoder.word(low)
    }
}
extension TaggedID: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try rawValue.encodeSource(to: &encoder)
    }
}

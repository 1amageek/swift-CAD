extension PortableIdentity128: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.tag(0x12, using: &admission); try encoder.word(high, using: &admission); try encoder.word(low, using: &admission)
    }
}
extension TaggedID: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try rawValue.encodeSource(to: &encoder, using: &admission)
    }
}

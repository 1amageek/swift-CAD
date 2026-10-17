import HashTreeCollections

extension TreeDictionary: PortableSourceEncodable where Key: PortableSourceEncodable, Value: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        let (retainedBytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<(Key, Value)>.stride)
        guard !overflow else { throw PortableSourceEncodingError.resourceLimitExceeded("Canonical persistent source map entries.") }
        try encoder.charge(bytes: retainedBytes, work: count, using: &admission)
        try encoder.map(map { ($0.key, $0.value) }, using: &admission)
    }
}

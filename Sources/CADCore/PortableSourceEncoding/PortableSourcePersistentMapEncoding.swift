import HashTreeCollections

extension TreeDictionary: PortableSourceEncodable where Key: PortableSourceEncodable, Value: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        let (retainedBytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<(Key, Value)>.stride)
        guard !overflow else { throw PortableSourceEncodingError.resourceLimitExceeded("Canonical persistent source map entries.") }
        try encoder.charge(bytes: retainedBytes, work: count)
        try encoder.map(map { ($0.key, $0.value) })
    }
}

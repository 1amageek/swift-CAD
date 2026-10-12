extension Bool: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.tag(self ? 0x02 : 0x01)
    }
}
extension String: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws { try encoder.text(self) }
}
extension Int: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.tag(0x03); try encoder.word(UInt64(bitPattern: Int64(self)))
    }
}
extension Int64: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.tag(0x04); try encoder.word(UInt64(bitPattern: self))
    }
}
extension UInt64: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.tag(0x05); try encoder.word(self)
    }
}
extension UInt32: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.tag(0x06); try encoder.word(UInt64(self))
    }
}
extension UInt8: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.tag(0x07); try encoder.tag(self)
    }
}
extension Double: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        guard isFinite else { throw PortableSourceEncodingError.nonfiniteScalar }
        try encoder.tag(0x08); try encoder.word(bitPattern)
    }
}
extension Optional: PortableSourceEncodable where Wrapped: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        switch self {
        case .none: try encoder.tag(0x00)
        case let .some(value): try encoder.tag(0x20); try encoder.value(value)
        }
    }
}
extension Array: PortableSourceEncodable where Element: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        try encoder.tag(0x21); try encoder.count(count)
        for value in self { try encoder.value(value) }
    }
}
extension Set: PortableSourceEncodable where Element: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        let (retainedBytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
        guard !overflow else { throw PortableSourceEncodingError.resourceLimitExceeded("Canonical source set storage.") }
        try encoder.charge(bytes: retainedBytes, work: count)
        let ordered = try encoder.canonicalOrder(Array(self))
        try encoder.tag(0x23); try encoder.count(ordered.count)
        for value in ordered { try encoder.value(value) }
    }
}
extension Dictionary: PortableSourceEncodable where Key: PortableSourceEncodable, Value: PortableSourceEncodable {
    public func encodeSource(to encoder: inout PortableSourceEncoder) throws {
        let (retainedBytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<(Key, Value)>.stride)
        guard !overflow else { throw PortableSourceEncodingError.resourceLimitExceeded("Canonical source map entries.") }
        try encoder.charge(bytes: retainedBytes, work: count)
        try encoder.map(map { ($0.key, $0.value) })
    }
}

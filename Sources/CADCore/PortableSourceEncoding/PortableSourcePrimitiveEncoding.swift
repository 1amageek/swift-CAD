extension Bool: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.tag(self ? 0x02 : 0x01, using: &admission)
    }
}
extension String: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws { try encoder.text(self, using: &admission) }
}
extension Int: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.tag(0x03, using: &admission); try encoder.word(UInt64(bitPattern: Int64(self)), using: &admission)
    }
}
extension Int64: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.tag(0x04, using: &admission); try encoder.word(UInt64(bitPattern: self), using: &admission)
    }
}
extension UInt64: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.tag(0x05, using: &admission); try encoder.word(self, using: &admission)
    }
}
extension UInt32: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.tag(0x06, using: &admission); try encoder.word(UInt64(self), using: &admission)
    }
}
extension UInt8: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.tag(0x07, using: &admission); try encoder.tag(self, using: &admission)
    }
}
extension Double: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        guard isFinite else { throw PortableSourceEncodingError.nonfiniteScalar }
        try encoder.tag(0x08, using: &admission); try encoder.word(bitPattern, using: &admission)
    }
}
extension Optional: PortableSourceEncodable where Wrapped: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        switch self {
        case .none: try encoder.tag(0x00, using: &admission)
        case let .some(value): try encoder.tag(0x20, using: &admission); try encoder.value(value, using: &admission)
        }
    }
}
extension Array: PortableSourceEncodable where Element: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        try encoder.tag(0x21, using: &admission); try encoder.count(count, using: &admission)
        for value in self { try encoder.value(value, using: &admission) }
    }
}
extension Set: PortableSourceEncodable where Element: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        let (retainedBytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<Element>.stride)
        guard !overflow else { throw PortableSourceEncodingError.resourceLimitExceeded("Canonical source set storage.") }
        try encoder.charge(bytes: retainedBytes, work: count, using: &admission)
        let ordered = try encoder.canonicalOrder(Array(self), using: &admission)
        try encoder.tag(0x23, using: &admission); try encoder.count(ordered.count, using: &admission)
        for value in ordered { try encoder.value(value, using: &admission) }
    }
}
extension Dictionary: PortableSourceEncodable where Key: PortableSourceEncodable, Value: PortableSourceEncodable {
    public func encodeSource<A: NumericWorkAdmission & ~Copyable>(to encoder: inout PortableSourceEncoder, using admission: inout A) throws {
        let (retainedBytes, overflow) = count.multipliedReportingOverflow(by: MemoryLayout<(Key, Value)>.stride)
        guard !overflow else { throw PortableSourceEncodingError.resourceLimitExceeded("Canonical source map entries.") }
        try encoder.charge(bytes: retainedBytes, work: count, using: &admission)
        try encoder.map(map { ($0.key, $0.value) }, using: &admission)
    }
}

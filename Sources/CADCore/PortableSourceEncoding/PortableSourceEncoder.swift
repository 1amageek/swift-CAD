/// Invocation-local canonical source bytes with cumulative output and scratch admission.
public struct PortableSourceEncoder {
    public let limits: PortableSourceEncodingLimits
    public private(set) var consumedBytes = 0
    public private(set) var consumedWork = 0
    private let retainsOutput: Bool
    private var depth = 0
    private var storage: [UInt8] = []

    public init(limits: PortableSourceEncodingLimits) throws {
        try limits.validate()
        self.limits = limits
        retainsOutput = true
    }

    private init(measuring limits: PortableSourceEncodingLimits) throws {
        try limits.validate()
        self.limits = limits
        retainsOutput = false
    }

    /// Measures the same source traversal without publishing or retaining output bytes.
    public static func measure<T: PortableSourceEncodable>(
        _ value: T, limits: PortableSourceEncodingLimits
    ) throws -> PortableSourceEncodingMeasurement {
        var encoder = try PortableSourceEncoder(measuring: limits)
        try encoder.value(value)
        return PortableSourceEncodingMeasurement(consumedBytes: encoder.consumedBytes,
            consumedWork: encoder.consumedWork)
    }

    public var bytes: [UInt8] { storage }

    public mutating func charge(bytes: Int = 0, work: Int = 0) throws {
        guard bytes >= 0, work >= 0,
              bytes <= limits.maximumBytes - consumedBytes,
              work <= limits.maximumWork - consumedWork else {
            throw PortableSourceEncodingError.resourceLimitExceeded("Cumulative source encoding allowance.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        consumedBytes += bytes
        consumedWork += work
    }

    public mutating func value<T: PortableSourceEncodable>(_ value: T) throws {
        guard depth < limits.maximumDepth else {
            throw PortableSourceEncodingError.resourceLimitExceeded("Source encoding depth.")
        }
        try charge(work: 1)
        depth += 1
        defer { depth -= 1 }
        try value.encodeSource(to: &self)
    }

    public mutating func field<T: PortableSourceEncodable>(_ name: String, _ value: T) throws {
        try text(name)
        try self.value(value)
    }

    public mutating func record(_ type: String, fields: Int) throws {
        try tag(0x30)
        try text(type)
        try count(fields)
    }

    public mutating func enumeration(_ type: String, caseName: String, values: Int) throws {
        try tag(0x31)
        try text(type)
        try text(caseName)
        try count(values)
    }

    public mutating func tag(_ value: UInt8) throws {
        try charge(bytes: 1, work: 1)
        if retainsOutput { storage.append(value) }
    }

    public mutating func word(_ value: UInt64) throws {
        try charge(bytes: 8, work: 8)
        if retainsOutput {
            for shift in stride(from: 56, through: 0, by: -8) {
                storage.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            }
        }
    }

    public mutating func count(_ value: Int) throws {
        guard value >= 0 else { throw PortableSourceEncodingError.invalidLimits }
        try word(UInt64(value))
    }

    public mutating func text(_ value: String) throws {
        let count = value.utf8.count
        try tag(0x10)
        try self.count(count)
        try charge(bytes: count, work: count)
        if retainsOutput { storage.append(contentsOf: value.utf8) }
    }

    public mutating func binary(_ value: [UInt8]) throws {
        try tag(0x11)
        try count(value.count)
        try charge(bytes: value.count, work: value.count)
        if retainsOutput { storage.append(contentsOf: value) }
    }

    /// Encodes scratch values under this invocation's remaining allowance, then retains their cost.
    private mutating func sortKey<T: PortableSourceEncodable>(_ value: T) throws -> [UInt8] {
        guard consumedBytes < limits.maximumBytes, consumedWork < limits.maximumWork else {
            throw PortableSourceEncodingError.resourceLimitExceeded("Canonical source key allowance.")
        }
        let remaining = PortableSourceEncodingLimits(
            maximumBytes: limits.maximumBytes - consumedBytes,
            maximumWork: limits.maximumWork - consumedWork,
            maximumDepth: limits.maximumDepth)
        var child = try PortableSourceEncoder(limits: remaining)
        child.depth = depth
        try child.value(value)
        try charge(bytes: child.consumedBytes, work: child.consumedWork)
        return child.storage
    }

    private mutating func compare(_ left: [UInt8], _ right: [UInt8]) throws -> Bool {
        let sharedCount = min(left.count, right.count)
        var index = 0
        while index < sharedCount {
            try charge(work: 1)
            if left[index] != right[index] { return left[index] < right[index] }
            index += 1
        }
        return left.count < right.count
    }

    /// Source sets preserve multiplicity but ignore source insertion order.
    public mutating func canonicalOrder<T: PortableSourceEncodable>(_ values: [T]) throws -> [T] {
        let (retainedBytes, overflow) = values.count.multipliedReportingOverflow(by: MemoryLayout<([UInt8], T)>.stride + MemoryLayout<T>.stride)
        guard !overflow else { throw PortableSourceEncodingError.resourceLimitExceeded("Canonical source entry storage.") }
        try charge(bytes: retainedBytes, work: values.count)
        var keyed: [([UInt8], T)] = []
        keyed.reserveCapacity(values.count)
        for value in values { keyed.append((try sortKey(value), value)) }
        try keyed.sort { try compare($0.0, $1.0) }
        return keyed.map { $0.1 }
    }

    public mutating func map<K: PortableSourceEncodable, V: PortableSourceEncodable>(_ entries: [(K, V)]) throws {
        let (entryBytes, overflow) = entries.count.multipliedReportingOverflow(by: MemoryLayout<([UInt8], V)>.stride)
        guard !overflow else { throw PortableSourceEncodingError.resourceLimitExceeded("Canonical source map storage.") }
        try charge(bytes: entryBytes, work: entries.count)
        var keyed: [([UInt8], V)] = []
        keyed.reserveCapacity(entries.count)
        for (key, value) in entries { keyed.append((try sortKey(key), value)) }
        try keyed.sort { try compare($0.0, $1.0) }
        try tag(0x22)
        try count(keyed.count)
        var previous: [UInt8]?
        for (key, value) in keyed {
            if let previous {
                try charge(work: min(previous.count, key.count))
                guard previous != key else { throw PortableSourceEncodingError.canonicalKeyCollision }
            }
            try charge(bytes: key.count, work: key.count)
            if retainsOutput { storage.append(contentsOf: key) }
            try self.value(value)
            previous = key
        }
    }
}

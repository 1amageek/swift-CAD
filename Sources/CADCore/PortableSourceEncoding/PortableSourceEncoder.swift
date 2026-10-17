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
    public static func measure<T: PortableSourceEncodable, A: NumericWorkAdmission & ~Copyable>(
        _ value: T, limits: PortableSourceEncodingLimits, using admission: inout A
    ) throws -> PortableSourceEncodingMeasurement {
        var encoder = try PortableSourceEncoder(measuring: limits)
        try encoder.value(value, using: &admission)
        return PortableSourceEncodingMeasurement(consumedBytes: encoder.consumedBytes,
            consumedWork: encoder.consumedWork)
    }

    public var bytes: [UInt8] { storage }

    private func checkCharge(bytes: Int, work: Int) throws {
        guard bytes >= 0, work >= 0,
              bytes <= limits.maximumBytes - consumedBytes,
              work <= limits.maximumWork - consumedWork else {
            throw PortableSourceEncodingError.resourceLimitExceeded("Cumulative source encoding allowance.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
    }

    public mutating func charge<A: NumericWorkAdmission & ~Copyable>(bytes: Int = 0, work: Int = 0, using admission: inout A) throws {
        try checkCharge(bytes: bytes, work: work)
        try admission.consumeWork(work)
        try admission.retainStorage(count: bytes, stride: MemoryLayout<UInt8>.stride)
        consumedBytes += bytes
        consumedWork += work
    }

    public mutating func value<T: PortableSourceEncodable, A: NumericWorkAdmission & ~Copyable>(_ value: T, using admission: inout A) throws {
        guard depth < limits.maximumDepth else {
            throw PortableSourceEncodingError.resourceLimitExceeded("Source encoding depth.")
        }
        try charge(work: 1, using: &admission)
        depth += 1
        defer { depth -= 1 }
        try value.encodeSource(to: &self, using: &admission)
        try admission.checkpoint()
    }

    public mutating func field<T: PortableSourceEncodable, A: NumericWorkAdmission & ~Copyable>(_ name: String, _ value: T, using admission: inout A) throws {
        try text(name, using: &admission)
        try self.value(value, using: &admission)
    }

    public mutating func record<A: NumericWorkAdmission & ~Copyable>(_ type: String, fields: Int, using admission: inout A) throws {
        try tag(0x30, using: &admission)
        try text(type, using: &admission)
        try count(fields, using: &admission)
    }

    public mutating func enumeration<A: NumericWorkAdmission & ~Copyable>(_ type: String, caseName: String, values: Int, using admission: inout A) throws {
        try tag(0x31, using: &admission)
        try text(type, using: &admission)
        try text(caseName, using: &admission)
        try count(values, using: &admission)
    }

    public mutating func tag<A: NumericWorkAdmission & ~Copyable>(_ value: UInt8, using admission: inout A) throws {
        try charge(bytes: 1, work: 1, using: &admission)
        if retainsOutput { storage.append(value) }
    }

    public mutating func word<A: NumericWorkAdmission & ~Copyable>(_ value: UInt64, using admission: inout A) throws {
        try charge(bytes: 8, work: 8, using: &admission)
        if retainsOutput {
            for shift in stride(from: 56, through: 0, by: -8) {
                storage.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
            }
        }
    }

    public mutating func count<A: NumericWorkAdmission & ~Copyable>(_ value: Int, using admission: inout A) throws {
        guard value >= 0 else { throw PortableSourceEncodingError.invalidLimits }
        try word(UInt64(value), using: &admission)
    }

    public mutating func text<A: NumericWorkAdmission & ~Copyable>(_ value: String, using admission: inout A) throws {
        let count = value.utf8.count
        try tag(0x10, using: &admission)
        try self.count(count, using: &admission)
        try charge(bytes: count, work: count, using: &admission)
        if retainsOutput { storage.append(contentsOf: value.utf8) }
    }

    public mutating func binary<A: NumericWorkAdmission & ~Copyable>(_ value: [UInt8], using admission: inout A) throws {
        try tag(0x11, using: &admission)
        try count(value.count, using: &admission)
        try charge(bytes: value.count, work: value.count, using: &admission)
        if retainsOutput { storage.append(contentsOf: value) }
    }

    /// Encodes scratch values under this invocation's remaining allowance, then retains their cost.
    private mutating func sortKey<T: PortableSourceEncodable, A: NumericWorkAdmission & ~Copyable>(_ value: T, using admission: inout A) throws -> [UInt8] {
        guard consumedBytes < limits.maximumBytes, consumedWork < limits.maximumWork else {
            throw PortableSourceEncodingError.resourceLimitExceeded("Canonical source key allowance.")
        }
        let remaining = PortableSourceEncodingLimits(
            maximumBytes: limits.maximumBytes - consumedBytes,
            maximumWork: limits.maximumWork - consumedWork,
            maximumDepth: limits.maximumDepth)
        var child = try PortableSourceEncoder(limits: remaining)
        child.depth = depth
        try child.value(value, using: &admission)
        // The child already admitted every operation on this same caller. Adopt only
        // the local encoding counters, preserving limits without charging twice.
        try checkCharge(bytes: child.consumedBytes, work: child.consumedWork)
        try admission.checkpoint()
        consumedBytes += child.consumedBytes
        consumedWork += child.consumedWork
        return child.storage
    }

    private mutating func compare<A: NumericWorkAdmission & ~Copyable>(_ left: [UInt8], _ right: [UInt8], using admission: inout A) throws -> Bool {
        let sharedCount = min(left.count, right.count)
        var index = 0
        while index < sharedCount {
            try charge(work: 1, using: &admission)
            if left[index] != right[index] { return left[index] < right[index] }
            index += 1
        }
        return left.count < right.count
    }

    /// Source sets preserve multiplicity but ignore source insertion order.
    public mutating func canonicalOrder<T: PortableSourceEncodable, A: NumericWorkAdmission & ~Copyable>(_ values: [T], using admission: inout A) throws -> [T] {
        let (retainedBytes, overflow) = values.count.multipliedReportingOverflow(by: MemoryLayout<([UInt8], T)>.stride + MemoryLayout<T>.stride)
        guard !overflow else { throw PortableSourceEncodingError.resourceLimitExceeded("Canonical source entry storage.") }
        try charge(bytes: retainedBytes, work: values.count, using: &admission)
        var keyed: [([UInt8], T)] = []
        keyed.reserveCapacity(values.count)
        for value in values { keyed.append((try sortKey(value, using: &admission), value)) }
        try keyed.sort { try compare($0.0, $1.0, using: &admission) }
        return keyed.map { $0.1 }
    }

    public mutating func map<K: PortableSourceEncodable, V: PortableSourceEncodable, A: NumericWorkAdmission & ~Copyable>(_ entries: [(K, V)], using admission: inout A) throws {
        let (entryBytes, overflow) = entries.count.multipliedReportingOverflow(by: MemoryLayout<([UInt8], V)>.stride)
        guard !overflow else { throw PortableSourceEncodingError.resourceLimitExceeded("Canonical source map storage.") }
        try charge(bytes: entryBytes, work: entries.count, using: &admission)
        var keyed: [([UInt8], V)] = []
        keyed.reserveCapacity(entries.count)
        for (key, value) in entries { keyed.append((try sortKey(key, using: &admission), value)) }
        try keyed.sort { try compare($0.0, $1.0, using: &admission) }
        try tag(0x22, using: &admission)
        try count(keyed.count, using: &admission)
        var previous: [UInt8]?
        for (key, value) in keyed {
            if let previous {
                try charge(work: min(previous.count, key.count), using: &admission)
                guard previous != key else { throw PortableSourceEncodingError.canonicalKeyCollision }
            }
            try charge(bytes: key.count, work: key.count, using: &admission)
            if retainsOutput { storage.append(contentsOf: key) }
            try self.value(value, using: &admission)
            previous = key
        }
    }
    /// Measures ordinary source authoring through the same admitted traversal.
    public static func measure<T: PortableSourceEncodable>(
        _ value: T, limits: PortableSourceEncodingLimits
    ) throws -> PortableSourceEncodingMeasurement {
        var admission = UnboundedAuthoringAdmission()
        return try measure(value, limits: limits, using: &admission)
    }

    public mutating func charge(bytes: Int = 0, work: Int = 0) throws {
        var admission = UnboundedAuthoringAdmission()
        try charge(bytes: bytes, work: work, using: &admission)
    }

    public mutating func value<T: PortableSourceEncodable>(_ value: T) throws {
        var admission = UnboundedAuthoringAdmission()
        try self.value(value, using: &admission)
    }

    public mutating func field<T: PortableSourceEncodable>(_ name: String, _ value: T) throws {
        var admission = UnboundedAuthoringAdmission()
        try field(name, value, using: &admission)
    }

    public mutating func record(_ type: String, fields: Int) throws {
        var admission = UnboundedAuthoringAdmission()
        try record(type, fields: fields, using: &admission)
    }

    public mutating func enumeration(_ type: String, caseName: String, values: Int) throws {
        var admission = UnboundedAuthoringAdmission()
        try enumeration(type, caseName: caseName, values: values, using: &admission)
    }

    public mutating func tag(_ value: UInt8) throws {
        var admission = UnboundedAuthoringAdmission()
        try tag(value, using: &admission)
    }

    public mutating func word(_ value: UInt64) throws {
        var admission = UnboundedAuthoringAdmission()
        try word(value, using: &admission)
    }

    public mutating func count(_ value: Int) throws {
        var admission = UnboundedAuthoringAdmission()
        try count(value, using: &admission)
    }

    public mutating func text(_ value: String) throws {
        var admission = UnboundedAuthoringAdmission()
        try text(value, using: &admission)
    }

    public mutating func binary(_ value: [UInt8]) throws {
        var admission = UnboundedAuthoringAdmission()
        try binary(value, using: &admission)
    }

    public mutating func canonicalOrder<T: PortableSourceEncodable>(_ values: [T]) throws -> [T] {
        var admission = UnboundedAuthoringAdmission()
        return try canonicalOrder(values, using: &admission)
    }

    public mutating func map<K: PortableSourceEncodable, V: PortableSourceEncodable>(_ entries: [(K, V)]) throws {
        var admission = UnboundedAuthoringAdmission()
        try map(entries, using: &admission)
    }

}

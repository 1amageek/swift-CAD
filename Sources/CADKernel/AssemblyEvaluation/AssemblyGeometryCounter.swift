import CADIR
import CADTopology

/// Counts retained geometry values without constructing a serialized buffer or control-net copy.
/// All encoder/container references remain inside one synchronous counting call.
struct AssemblyGeometryCounter: Encoder {
    private final class Budget {
        var count = 0
        let maximum: Int
        init(maximum: Int) { self.maximum = maximum }
        func charge(_ count: Int) throws {
            guard count >= 0, count <= maximum - self.count else {
                throw AssemblyError.resourceLimitExceeded("geometry values")
            }
            self.count += count
        }
    }
    private let budget: Budget
    private let depth: Int
    private let maximumDepth: Int
    let codingPath: [any CodingKey] = []
    let userInfo: [CodingUserInfoKey: Any] = [:]
    static func count(_ model: BRepModel, maximum: Int, maximumDepth: Int) throws -> Int {
        let budget = Budget(maximum: maximum)
        // Traverse persistent-map values directly: counting never asks a map encoder to
        // materialize a dictionary, and each geometry payload retains its existing storage.
        let encoder = AssemblyGeometryCounter(budget: budget, depth: 0, maximumDepth: maximumDepth)
        for curve in model.geometry.curves.values {
            try budget.charge(1)
            try curve.encode(to: encoder)
        }
        for surface in model.geometry.surfaces.values {
            try budget.charge(1)
            try surface.encode(to: encoder)
        }
        // Loop payloads own trim/control arrays independently of 3D geometry records.
        for loop in model.loops.values {
            try budget.charge(1)
            try loop.encode(to: encoder)
        }
        return budget.count
    }
    private func child() throws -> AssemblyGeometryCounter {
        guard depth < maximumDepth else { throw AssemblyError.resourceLimitExceeded("geometry nesting") }
        return AssemblyGeometryCounter(budget: budget, depth: depth + 1, maximumDepth: maximumDepth)
    }
    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(Keyed<Key>(encoder: self))
    }
    func unkeyedContainer() -> any UnkeyedEncodingContainer { Unkeyed(encoder: self) }
    func singleValueContainer() -> any SingleValueEncodingContainer { Single(encoder: self) }
    private struct Keyed<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let encoder: AssemblyGeometryCounter
        var codingPath: [any CodingKey] { [] }
        mutating func encodeNil(forKey key: Key) throws { try encoder.budget.charge(1) }
        mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
            try encoder.budget.charge(1); try value.encode(to: encoder.child())
        }
        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> { encoder.container(keyedBy: type) }
        mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer { encoder.unkeyedContainer() }
        mutating func superEncoder() -> any Encoder { encoder }
        mutating func superEncoder(forKey key: Key) -> any Encoder { encoder }
    }
    private struct Unkeyed: UnkeyedEncodingContainer {
        let encoder: AssemblyGeometryCounter
        var codingPath: [any CodingKey] { [] }
        var count = 0
        mutating func encodeNil() throws { count += 1; try encoder.budget.charge(1) }
        mutating func encode<T: Encodable>(_ value: T) throws {
            count += 1; try encoder.budget.charge(1); try value.encode(to: encoder.child())
        }
        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> { encoder.container(keyedBy: type) }
        mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer { encoder.unkeyedContainer() }
        mutating func superEncoder() -> any Encoder { encoder }
    }
    private struct Single: SingleValueEncodingContainer {
        let encoder: AssemblyGeometryCounter
        var codingPath: [any CodingKey] { [] }
        mutating func encodeNil() throws { try encoder.budget.charge(1) }
        mutating func encode<T: Encodable>(_ value: T) throws { try value.encode(to: encoder.child()) }
        mutating func encode(_ value: Bool) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: String) throws { try encoder.budget.charge(value.utf8.count) }
        mutating func encode(_ value: Double) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: Float) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: Int) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: Int8) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: Int16) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: Int32) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: Int64) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: UInt) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: UInt8) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: UInt16) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: UInt32) throws { try encoder.budget.charge(1) }
        mutating func encode(_ value: UInt64) throws { try encoder.budget.charge(1) }
    }
}

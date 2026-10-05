import Foundation
import CADCore
import Synchronization

/// Native token serialization under the composing invocation's actual payload ceiling.
struct NativeBoundedJSONEncoder {
    func encode<T: Encodable>(_ value: T, canonicalDocument: Bool = false,
        resources: any NativeJSONAccounting) throws -> Data {
        let context = Context(resources: resources)
        let root = try context.node(path: [])
        try ValueEncoder(node: root, context: context, codingPath: []).encode(value)
        try context.check()
        if canonicalDocument { try canonicalizeDocument(root, context: context) }
        var output = Data()
        try render(root, context: context, into: &output)
        try context.check()
        return output
    }

    private final class Context: Sendable {
        let resources: any NativeJSONAccounting
        let failure = Mutex<(any Error)?>(nil)
        init(resources: any NativeJSONAccounting) { self.resources = resources }
        func check() throws {
            try resources.checkTime()
            if let error = failure.withLock({ $0 }) { throw error }
        }
        func deferFailure(_ body: () throws -> Void) {
            do { try body() } catch { failure.withLock { if $0 == nil { $0 = error } } }
        }
        func node(path: [any CodingKey]) throws -> Node {
            try check(); try resources.validateNestingDepth(path.count)
            try resources.charge(entities: 1, work: 1)
            return Node()
        }
        func string(_ value: String, bytesAlreadyAdmitted: Bool = false) throws -> Data {
            var count = 2
            for byte in value.utf8 {
                try resources.recordIterations()
                let increment = byte < 0x20 ? 6 : (byte == 0x22 || byte == 0x5c || byte == 0x2f ? 2 : 1)
                let next = count.addingReportingOverflow(increment)
                guard !next.overflow else { throw exchangeResourceLimitError(format: resources.format, detail: "JSON string size overflows") }
                count = next.partialValue
            }
            if !bytesAlreadyAdmitted { try resources.recordBytes(count) }
            var result = Data(); result.reserveCapacity(count); result.append(0x22)
            let hex: [UInt8] = Array("0123456789abcdef".utf8)
            for byte in value.utf8 {
                try resources.recordIterations()
                if byte < 0x20 { result.append(contentsOf: [0x5c, 0x75, 0x30, 0x30, hex[Int(byte >> 4)], hex[Int(byte & 15)]]) }
                else if byte == 0x22 || byte == 0x5c || byte == 0x2f { result.append(0x5c); result.append(byte) }
                else { result.append(byte) }
            }
            result.append(0x22); return result
        }
        func scalar<T: Encodable>(_ value: T) throws -> Data {
            try check(); try resources.recordIterations()
            // Fixed-width scalar codecs cannot materialize a source-sized buffer.
            let result = try JSONEncoder().encode(value)
            try resources.recordBytes(result.count); return result
        }
    }
    private final class Node: Sendable {
        enum Payload: Sendable {
            case unset, scalar(Data), object([Entry]), array([Node])
        }
        struct Entry: Sendable { let key: String; let token: Data; let value: Node }
        private struct State: Sendable {
            var kind = 0
            var scalar = Data()
            var object: [Entry] = []
            var array: [Node] = []
        }
        private let state = Mutex(State())
        func snapshot() -> Payload {
            state.withLock { value in
                switch value.kind {
                case 1: return .scalar(value.scalar)
                case 2: return .object(value.object)
                case 3: return .array(value.array)
                default: return .unset
                }
            }
        }
        func replaceWithArray(_ values: [Node]) {
            state.withLock { $0.kind = 3; $0.object = []; $0.array = values }
        }
        func container(array: Bool, context: Context) throws {
            try context.check()
            let requested = array ? 3 : 2
            let old = state.withLock { value -> Int in
                let old = value.kind
                if old == 0 { value.kind = requested }
                return old
            }
            if old == 0 { try context.resources.recordBytes(2) }
            else if old != requested { throw EncodingError.invalidValue("container", .init(codingPath: [], debugDescription: "Conflicting Native JSON containers.")) }
        }
        func scalar(_ bytes: Data, context: Context) throws {
            try context.check()
            try state.withLock { value in
                guard value.kind == 0 else { throw EncodingError.invalidValue("scalar", .init(codingPath: [], debugDescription: "Native value encoded more than once.")) }
                value.kind = 1; value.scalar = bytes
            }
        }
        func append(_ child: Node, key: String?, context: Context) throws {
            try context.check()
            if let key {
                let token = try context.string(key)
                let count = try state.withLock { value -> Int in
                    guard value.kind == 2 else { throw EncodingError.invalidValue(key, .init(codingPath: [], debugDescription: "Invalid Native object container.")) }
                    return value.object.count
                }
                try context.resources.recordBytes(count == 0 ? 1 : 2)
                try context.resources.recordIterations(count)
                try state.withLock { value in
                    guard !value.object.contains(where: { $0.key == key }) else {
                        throw EncodingError.invalidValue(key, .init(codingPath: [], debugDescription: "Duplicate Native object key."))
                    }
                    value.object.append(.init(key: key, token: token, value: child))
                }
            } else {
                let count = try state.withLock { value -> Int in
                    guard value.kind == 3 else { throw EncodingError.invalidValue("array", .init(codingPath: [], debugDescription: "Invalid Native array container.")) }
                    return value.array.count
                }
                if count > 0 { try context.resources.recordBytes(1) }
                state.withLock { $0.array.append(child) }
            }
        }
        var arrayCount: Int { state.withLock { $0.array.count } }
    }
    private struct IndexKey: CodingKey {
        let stringValue: String; let intValue: Int?
        init(_ value: Int) { stringValue = "Index \(value)"; intValue = value }
        init(name: String) { stringValue = name; intValue = nil }
        init?(stringValue: String) { self.stringValue = stringValue; intValue = nil }
        init?(intValue: Int) { self.init(intValue) }
    }
    private struct ValueEncoder: Encoder {
        let node: Node; let context: Context; let codingPath: [any CodingKey]
        var userInfo: [CodingUserInfoKey: Any] { [:] }
        func encode<T: Encodable>(_ value: T) throws {
            try context.check()
            if let date = value as? Date { var c = singleValueContainer(); try c.encode(date.timeIntervalSinceReferenceDate) }
            else if let data = value as? Data {
                let n = data.count.addingReportingOverflow(2)
                let groups = n.partialValue / 3
                let body = groups.multipliedReportingOverflow(by: 4)
                let quoted = body.partialValue.addingReportingOverflow(2)
                guard !n.overflow, !body.overflow, !quoted.overflow,
                    quoted.partialValue <= context.resources.limits.maximumBytes - context.resources.byteCount else {
                    throw exchangeResourceLimitError(format: context.resources.format, detail: "Native base64 value exceeds payload ceiling")
                }
                try context.resources.recordBytes(quoted.partialValue)
                try context.resources.recordIterations(data.count)
                // JSON slash escaping is retained and admitted before its quoted token is allocated.
                let text = data.base64EncodedString()
                var extra = 0
                for byte in text.utf8 { try context.resources.recordIterations(); if byte == 0x2f { extra += 1 } }
                try context.resources.recordBytes(extra)
                try node.scalar(context.string(text, bytesAlreadyAdmitted: true), context: context)
            } else { try value.encode(to: self) }
        }
        func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
            context.deferFailure { try node.container(array: false, context: context) }
            return .init(Keyed<Key>(encoder: self))
        }
        func unkeyedContainer() -> any UnkeyedEncodingContainer {
            context.deferFailure { try node.container(array: true, context: context) }
            return Unkeyed(encoder: self)
        }
        func singleValueContainer() -> any SingleValueEncodingContainer { Single(encoder: self) }
        func child(_ key: (any CodingKey)?, arrayIndex: Int = 0) throws -> Self {
            let path = codingPath + [key ?? IndexKey(arrayIndex)]
            let child = try context.node(path: path)
            try node.append(child, key: key?.stringValue, context: context)
            return Self(node: child, context: context, codingPath: path)
        }
    }
    private struct Keyed<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let encoder: ValueEncoder
        var codingPath: [any CodingKey] { encoder.codingPath }
        mutating func encode(_ value: String, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: Bool, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: Double, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: Float, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: Int, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: Int8, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: Int16, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: Int32, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: Int64, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: UInt, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: UInt8, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: UInt16, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: UInt32, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encode(_ value: UInt64, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func encodeNil(forKey key: Key) throws { var c = try encoder.child(key).singleValueContainer(); try c.encodeNil() }
        mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { try encoder.child(key).encode(value) }
        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
            var result = KeyedEncodingContainer(Keyed<NestedKey>(encoder: encoder))
            encoder.context.deferFailure { result = try encoder.child(key).container(keyedBy: keyType) }; return result
        }
        mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
            var result: any UnkeyedEncodingContainer = Unkeyed(encoder: encoder)
            encoder.context.deferFailure { result = try encoder.child(key).unkeyedContainer() }; return result
        }
        mutating func superEncoder() -> any Encoder {
            var result = encoder; encoder.context.deferFailure { result = try encoder.child(IndexKey(name: "super")) }; return result
        }
        mutating func superEncoder(forKey key: Key) -> any Encoder {
            var result = encoder; encoder.context.deferFailure { result = try encoder.child(key) }; return result
        }
    }
    private struct Unkeyed: UnkeyedEncodingContainer {
        let encoder: ValueEncoder
        var codingPath: [any CodingKey] { encoder.codingPath }
        var count: Int { encoder.node.arrayCount }
        mutating func encode(_ value: String) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: Bool) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: Double) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: Float) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: Int) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: Int8) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: Int16) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: Int32) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: Int64) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: UInt) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: UInt8) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: UInt16) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: UInt32) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encode(_ value: UInt64) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func encodeNil() throws { var c = try encoder.child(nil, arrayIndex: count).singleValueContainer(); try c.encodeNil() }
        mutating func encode<T: Encodable>(_ value: T) throws { try encoder.child(nil, arrayIndex: count).encode(value) }
        mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
            var result = KeyedEncodingContainer(Keyed<NestedKey>(encoder: encoder))
            encoder.context.deferFailure { result = try encoder.child(nil, arrayIndex: count).container(keyedBy: keyType) }; return result
        }
        mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
            var result: any UnkeyedEncodingContainer = Unkeyed(encoder: encoder)
            encoder.context.deferFailure { result = try encoder.child(nil, arrayIndex: count).unkeyedContainer() }; return result
        }
        mutating func superEncoder() -> any Encoder {
            var result = encoder; encoder.context.deferFailure { result = try encoder.child(nil, arrayIndex: count) }; return result
        }
    }
    private struct Single: SingleValueEncodingContainer {
        let encoder: ValueEncoder
        var codingPath: [any CodingKey] { encoder.codingPath }
        mutating func encodeNil() throws { try encoder.context.resources.recordBytes(4); try encoder.node.scalar(Data("null".utf8), context: encoder.context) }
        mutating func encode(_ value: String) throws { try encoder.node.scalar(encoder.context.string(value), context: encoder.context) }
        mutating func encode(_ value: Bool) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: Double) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: Float) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: Int) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: Int8) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: Int16) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: Int32) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: Int64) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: UInt) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: UInt8) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: UInt16) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: UInt32) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode(_ value: UInt64) throws { try encoder.node.scalar(encoder.context.scalar(value), context: encoder.context) }
        mutating func encode<T: Encodable>(_ value: T) throws { try encoder.encode(value) }
    }

    private func render(_ node: Node, context: Context, into output: inout Data) throws {
        try context.check(); try context.resources.recordIterations()
        func append(_ bytes: Data) throws {
            guard bytes.count <= context.resources.limits.maximumBytes - output.count else {
                throw exchangeResourceLimitError(format: context.resources.format, detail: "Native JSON output exceeds payload ceiling")
            }
            output.append(bytes)
        }
        switch node.snapshot() {
        case .unset: throw EncodingError.invalidValue("unset", .init(codingPath: [], debugDescription: "Native value did not encode any representation."))
        case .scalar(let bytes): try append(bytes)
        case .array(let values):
            try append(Data("[".utf8))
            for (index, value) in values.enumerated() { if index > 0 { try append(Data(",".utf8)) }; try render(value, context: context, into: &output) }
            try append(Data("]".utf8))
        case .object(var values):
            try values.sort { lhs, rhs in
                try context.resources.recordIterations(lhs.key.utf8.count + rhs.key.utf8.count + 1)
                return lhs.key < rhs.key
            }
            try context.check(); try append(Data("{".utf8))
            for (index, value) in values.enumerated() {
                if index > 0 { try append(Data(",".utf8)) }; try append(value.token); try append(Data(":".utf8))
                try render(value.value, context: context, into: &output)
            }
            try append(Data("}".utf8))
        }
    }

    private func canonicalizeDocument(_ root: Node, context: Context) throws {
        func member(_ node: Node, _ key: String) -> Node? {
            if case .object(let entries) = node.snapshot() { return entries.first(where: { $0.key == key })?.value }; return nil
        }
        func dynamic(_ node: Node) throws {
            var pairs: [(String, Node, Node)] = []
            switch node.snapshot() {
            case .object(let entries):
                for entry in entries {
                    try context.resources.recordIterations()
                    let key = try context.node(path: [])
                    try key.scalar(entry.token, context: context)
                    pairs.append((entry.key, key, entry.value))
                }
            case .array(let entries):
                guard entries.count.isMultiple(of: 2) else { throw SchemaError.invalidPackage("Native dynamic dictionary requires pairs.") }
                var index = 0
                while index < entries.count {
                    try context.resources.recordIterations()
                    guard case .scalar(let bytes) = entries[index].snapshot() else { throw SchemaError.invalidPackage("Native dynamic key must be a string.") }
                    let key = try JSONDecoder().decode(String.self, from: bytes)
                    pairs.append((key, entries[index], entries[index+1])); index += 2
                }
            default: return
            }
            var canonical: [(String, Node, Node)] = []
            for pair in pairs {
                try context.resources.recordIterations(pair.0.utf8.count + 1)
                let identity = try PortableIdentity128(canonicalString: pair.0)
                canonical.append((identity.canonicalString, pair.1, pair.2))
            }
            try canonical.sort { a, b in
                try context.resources.recordIterations(a.0.utf8.count + b.0.utf8.count + 1); return a.0 < b.0
            }
            try context.check()
            var values: [Node] = []
            for pair in canonical { values.append(pair.1); values.append(pair.2) }
            node.replaceWithArray(values)
        }
        if let parameters = member(root, "parameters"), let values = member(parameters, "parameters") { try dynamic(values) }
        if let graph = member(root, "designGraph"), let nodes = member(graph, "nodes") {
            try dynamic(nodes)
            if case .array(let pairs) = nodes.snapshot() {
                var index = 1
                while index < pairs.count {
                    try context.resources.recordIterations()
                    if let operation = member(pairs[index], "operation"), let sketch = member(operation, "sketch"), let entities = member(sketch, "entities") { try dynamic(entities) }
                    index += 2
                }
            }
        }
    }
}

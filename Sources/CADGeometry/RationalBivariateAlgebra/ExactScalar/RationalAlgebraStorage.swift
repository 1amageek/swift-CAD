/// Direct byte admission preserving the original UInt32 payload rounding policy.
package enum RationalAlgebraStorage {
    package static func retain<T, B: ExactScalarAdmission & ~Copyable>(_ count: Int, of type: T.Type,
        usage: inout B) throws {
        try retainBytes(exactScalarPayloadBytes(count: count, of: type), usage: &usage)
    }
    package static func retainBytes<B: ExactScalarAdmission & ~Copyable>(_ bytes: Int, usage: inout B) throws {
        let stride = MemoryLayout<UInt32>.stride
        let words = try exactScalarCount(bytes, stride - 1) / stride
        try usage.retainStorage(bytes: exactScalarPayloadBytes(count: words, of: UInt32.self))
    }
}

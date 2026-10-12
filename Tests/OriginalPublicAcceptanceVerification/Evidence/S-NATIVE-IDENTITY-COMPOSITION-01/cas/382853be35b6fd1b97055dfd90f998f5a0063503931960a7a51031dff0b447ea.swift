/// Checked payload storage admission in the original UInt32-word ledger.
package enum RationalAlgebraStorage {
    package static func retain<T, B: RationalAlgebraAdmitting>(_ count: Int, of type: T.Type,
        usage: inout B) throws {
        try retainBytes(exactScalarPayloadBytes(count: count, of: type), usage: &usage)
    }
    package static func retainBytes<B: RationalAlgebraAdmitting>(_ bytes: Int, usage: inout B) throws {
        let stride = MemoryLayout<UInt32>.stride
        let words = try exactScalarCount(bytes, stride - 1) / stride
        try usage.retainExactStorage(words)
    }
}

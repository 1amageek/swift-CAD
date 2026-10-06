/// Checked payload storage admission in the original UInt32-word ledger.
enum RationalAlgebraStorage {
    static func retain<T, B: RationalAlgebraAdmitting>(_ count: Int, of type: T.Type,
        usage: inout B) throws {
        try retainBytes(rationalAlgebraCount(count, MemoryLayout<T>.stride, multiply: true), usage: &usage)
    }
    static func retainBytes<B: RationalAlgebraAdmitting>(_ bytes: Int, usage: inout B) throws {
        let stride = MemoryLayout<UInt32>.stride
        let words = try rationalAlgebraCount(bytes, stride - 1) / stride
        try usage.retainExactStorage(words)
    }
}

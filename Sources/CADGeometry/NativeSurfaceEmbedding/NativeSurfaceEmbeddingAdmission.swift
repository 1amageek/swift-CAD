import CADCore

/// Immutable composing ledger; the caller owns every retained counter and its isolation.
public struct NativeSurfaceEmbeddingAdmission: Sendable {
    private let consume: @Sendable (Int) throws -> Void
    private let visit: @Sendable (Int) throws -> Void
    private let retain: @Sendable (Int) throws -> Void

    public init(consumeWork: @escaping @Sendable (Int) throws -> Void,
        visitCell: @escaping @Sendable (Int) throws -> Void,
        retainStorage: @escaping @Sendable (Int) throws -> Void) {
        consume = consumeWork; visit = visitCell; retain = retainStorage
    }

    /// Existing local algorithm ceilings still bind when no outer ledger is composed.
    public static let legacy = Self(consumeWork: { _ in }, visitCell: { _ in }, retainStorage: { _ in })

    func shifted(by offset: Int) throws -> Self {
        guard offset >= 0 else { throw GeometryConversionError.invalidInput("Native causal depth offset cannot be negative.") }
        return Self(consumeWork: { try self.work($0) }, visitCell: { depth in
            let sum = depth.addingReportingOverflow(offset)
            guard !sum.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native causal depth overflows.") }
            try self.cell(depth: sum.partialValue)
        }, retainStorage: { try self.storageWords($0) })
    }

    func work(_ units: Int) throws {
        try Task.checkCancellation()
        guard units >= 0 else { throw GeometryConversionError.invalidInput("Native embedding work cannot be negative.") }
        try consume(units)
    }
    func cell(depth: Int) throws {
        try Task.checkCancellation()
        guard depth >= 0 else { throw GeometryConversionError.invalidInput("Native embedding depth cannot be negative.") }
        try visit(depth)
    }
    func storageBytes(_ bytes: Int) throws {
        guard bytes >= 0 else { throw GeometryConversionError.invalidInput("Native storage byte count cannot be negative.") }
        let quantum = MemoryLayout<UInt32>.stride
        let padded = bytes.addingReportingOverflow(quantum - 1)
        guard !padded.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native byte reservation overflows.") }
        try storageWords(padded.partialValue / quantum)
    }
    func storageElements<T>(_ count: Int, of type: T.Type) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<T>.stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Native retained element byte count overflows.")
        }
        try storageBytes(bytes.partialValue)
    }
    /// Native local reservation sites retain their original 64-bit slot unit.
    func storage(_ slots: Int) throws {
        guard slots >= 0 else { throw GeometryConversionError.invalidInput("Native embedding storage cannot be negative.") }
        let words = slots.multipliedReportingOverflow(by: 2)
        guard !words.overflow else { throw GeometryConversionError.resourceLimitExceeded("Native slot conversion overflows.") }
        try storageWords(words.partialValue)
    }
    /// Exact source algebra already reserves canonical UInt32 words.
    func storageWords(_ words: Int) throws {
        try Task.checkCancellation()
        guard words >= 0 else { throw GeometryConversionError.invalidInput("Native retained word count cannot be negative.") }
        try retain(words)
    }
}

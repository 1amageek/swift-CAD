import CADCore
import CADGeometry

/// Borrows the original invocation ledger without creating another allowance.
package struct OriginalSourceProofAdmission: RationalAlgebraAdmitting {
    let consumeWork: (@Sendable (Int) throws -> Void)?
    let maximumAlgebraicDepth: Int?
    let consumeStorage: (@Sendable (Int) throws -> Void)?

    package init(consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) {
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        self.consumeWork = consumeWork
        self.consumeStorage = consumeStorage
    }

    package mutating func visitExactCell(depth: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard depth >= 0, maximumAlgebraicDepth.map({ (0...32).contains($0) && depth <= $0 }) ?? true else {
            throw KernelError(phase: .topology, code: .resourceLimitExceeded,
                tolerance: nil, message: "Original algebra proof exceeds its independent caller ceiling.")
        }
        // Producer algebra depth remains distinct from source recursion and
        // geometric subdivision; selected callers retain its independent cap.
        try consumeWork?(0)
    }

    package mutating func consumeExactWork(_ count: Int) throws {
        guard count >= 0 else {
            throw KernelError(phase: .topology, code: .resourceLimitExceeded,
                tolerance: nil, message: "Original source proof work count is negative.")
        }
        for _ in 0..<count { try visitExactCell(depth: 0) }
    }

    package mutating func retainExactStorage(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else {
            throw KernelError(phase: .topology, code: .resourceLimitExceeded,
                tolerance: nil, message: "Original proof word-byte accounting overflowed.")
        }
        try CurrentTaskCancellationChecker().checkCancellation(); try consumeStorage?(bytes.partialValue)
        try consumeExactWork(count)
    }
}

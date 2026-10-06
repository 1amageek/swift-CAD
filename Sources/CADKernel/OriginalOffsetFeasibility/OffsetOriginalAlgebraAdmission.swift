import CADCore
import CADGeometry

/// Adapts the exact source issuer to the composing result invocation, without
/// creating a new cumulative work or storage allowance.
struct OffsetOriginalAlgebraAdmission: RationalAlgebraAdmitting {
    let maximumAlgebraicDepth: Int
    let tolerance: ModelingTolerance
    let consumeWork: @Sendable (Int) throws -> Void
    let consumeStorage: (@Sendable (Int) throws -> Void)?

    mutating func visitExactCell(depth: Int) throws {
        try Task.checkCancellation()
        guard (0...32).contains(maximumAlgebraicDepth), depth >= 0,
              depth <= maximumAlgebraicDepth else {
            throw failure("Original offset continuity exceeded its independently selected algebra depth.")
        }
        // Exact coefficient depth is independent of the spatial visit depth.
        try consumeWork(0)
    }

    mutating func visitCoefficientCell(depth: Int) throws {
        try visitExactCell(depth: depth)
    }

    mutating func consumeExactWork(_ count: Int) throws {
        guard count >= 0 else { throw failure("Original offset continuity has a negative work request.") }
        for _ in 0..<count {
            try Task.checkCancellation()
            try consumeWork(0)
        }
    }

    mutating func retainExactStorage(_ count: Int) throws {
        try Task.checkCancellation()
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else {
            throw failure("Original offset continuity storage-byte conversion overflowed.")
        }
        try consumeStorage?(bytes.partialValue)
    }

    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .topology, code: .resourceLimitExceeded,
            tolerance: tolerance, message: message)
    }
}

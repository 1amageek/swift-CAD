import CADCore
import Synchronization

/// One invocation owns all original station and trimmed-facet proof visits.
final class TessellationProofBudget: Sendable {
    private let state = Mutex(262_144)
    var remaining: Int { state.withLock { $0 } }

    func charge(_ count: Int = 1) throws {
        let admitted = state.withLock { remaining in
            guard count >= 0,count <= remaining else { return false }
            remaining -= count
            return true
        }
        guard admitted else { throw failure() }
        try Task.checkCancellation()
    }

    /// Admits original byte payloads in the retained UInt32-word unit.
    func chargeStorageBytes(_ bytes: Int) throws {
        let stride = MemoryLayout<UInt32>.stride
        guard bytes >= 0 else { throw failure() }
        let whole = bytes / stride
        let rounded = whole.addingReportingOverflow(bytes % stride == 0 ? 0 : 1)
        guard !rounded.overflow else { throw failure() }
        try charge(rounded.partialValue)
    }

    func charge(depth: Int) throws {
        guard (0...32).contains(depth) else {
            throw KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: nil,
                message: "Original mesh proof exceeded its existing subdivision depth ceiling.")
        }
        try charge()
    }

    /// Reserves the remaining allowance before an inout-budget Geometry call.
    /// The computation runs outside the lock; unused visits return to the owner.
    func withRemainingCells<Result>(_ body: (inout Int) throws -> Result) throws -> Result {
        let reserved = state.withLock { remaining in
            let count = remaining
            remaining = 0
            return count
        }
        guard reserved > 0 else { throw failure() }
        var remainder = reserved
        do {
            let result = try body(&remainder)
            guard remainder >= 0,remainder <= reserved else { throw failure() }
            state.withLock { $0 += remainder }
            return result
        } catch {
            if remainder >= 0,remainder <= reserved { state.withLock { $0 += remainder } }
            throw error
        }
    }
    private func failure() -> KernelError {
        KernelError(phase: .geometry,code: .resourceLimitExceeded,tolerance: nil,
            message: "Original mesh proof exceeded its shared 262144-visit allowance.")
    }
}

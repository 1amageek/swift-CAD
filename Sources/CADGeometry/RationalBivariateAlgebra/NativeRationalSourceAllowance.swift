#if !hasFeature(Embedded)
import CADCore
import Synchronization

/// One decoder-owned caller allowance shared by every nested original source value.
@available(macOS 15.0, iOS 18.0, visionOS 2.0, watchOS 11.0, tvOS 18.0, *)
public final class NativeRationalSourceAllowance: Sendable, RationalAlgebraAdmitting {
    private struct State: Sendable {
        var work = 0
        var cells = 0
        var storage = 0
    }
    public let maximumWork: Int
    public let maximumCells: Int
    public let maximumStorage: Int
    public let maximumDepth: Int
    private let state: Mutex<State>
    private let operationCheck: @Sendable () throws -> Void

    public init(maximumWork: Int, maximumCells: Int, maximumStorage: Int, maximumDepth: Int,
                operationCheck: @escaping @Sendable () throws -> Void) throws {
        guard maximumWork >= 0, maximumCells >= 0, maximumStorage >= 0, maximumDepth >= 0 else {
            throw rationalAlgebraFailure("Native original source admission requires nonnegative caller limits.")
        }
        self.maximumWork = maximumWork; self.maximumCells = maximumCells
        self.maximumStorage = maximumStorage; self.maximumDepth = maximumDepth
        self.operationCheck = operationCheck
        state = Mutex(State())
    }
    public func consumeExactWork(_ count: Int) throws {
        try operationCheck()
        try Task.checkCancellation()
        try state.withLock { value in
            guard count >= 0, count <= maximumWork - value.work else {
                throw exhausted("Native original source work exceeds the composing caller allowance.")
            }
            value.work += count
        }
    }
    public func retainExactStorage(_ count: Int) throws {
        try operationCheck()
        try Task.checkCancellation()
        try state.withLock { value in
            guard count >= 0, count <= maximumStorage - value.storage else {
                throw exhausted("Native original source storage exceeds the composing caller allowance.")
            }
            value.storage += count
        }
    }
    public func visitExactCell(depth: Int) throws {
        try operationCheck()
        try Task.checkCancellation()
        try state.withLock { value in
            guard depth >= 0, depth <= maximumDepth, value.cells < maximumCells else {
                throw exhausted("Native original source cells or retained path depth exceed caller allowance.")
            }
            value.cells += 1
        }
    }
    public func snapshot() throws -> NativeRationalSourceAllowanceSnapshot {
        try operationCheck()
        try Task.checkCancellation()
        return state.withLock { value in
            NativeRationalSourceAllowanceSnapshot(maximumWork: maximumWork,
                maximumCells: maximumCells, maximumStorage: maximumStorage,
                maximumDepth: maximumDepth, work: value.work, cells: value.cells, storage: value.storage)
        }
    }
    private func exhausted(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil, message: message)
    }
}
#endif

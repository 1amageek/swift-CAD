import CADCore
import Synchronization

/// One original distance invocation owns all adaptive proof visits.
package final class BRepDistanceProofBudget: Sendable {
    private struct State: Sendable { var consumed = 0; var consumedBytes = 0 }
    private let state = Mutex(State())
    private let tolerance: ModelingTolerance
    private let maximumWork: Int
    package let maximumDepth: Int
    package let maximumSourceDepth: Int
    package let maximumAlgebraicDepth: Int
    private let maximumCumulativeStorageBytes: Int?
    private let externalWorkAdmission: (@Sendable (Int) throws -> Void)?
    private let externalStorageAdmission: (@Sendable (Int) throws -> Void)?

    package init(tolerance: ModelingTolerance, maximumWork: Int, maximumDepth: Int,
        maximumCumulativeStorageBytes: Int? = nil, maximumSourceDepth: Int = 16,
        maximumAlgebraicDepth: Int = 32,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil,
        consumeStorage: (@Sendable (Int) throws -> Void)? = nil) {
        self.tolerance = tolerance
        self.maximumWork = maximumWork
        self.maximumDepth = maximumDepth
        self.maximumCumulativeStorageBytes = maximumCumulativeStorageBytes
        self.maximumSourceDepth = maximumSourceDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        externalWorkAdmission = consumeWork
        externalStorageAdmission = consumeStorage
    }

    package var consumedStorageBytes: Int { state.withLock { $0.consumedBytes } }

    package var storageAdmission: (@Sendable (Int) throws -> Void)? {
        guard maximumCumulativeStorageBytes != nil || externalStorageAdmission != nil else { return nil }
        return { [self] count in try chargeStorageBytes(count) }
    }

    package var consumedWork: Int { state.withLock { $0.consumed } }

    package func isBound(to options: BRepDistanceOptions, tolerance: ModelingTolerance) -> Bool {
        self.tolerance == tolerance && maximumWork == options.maximumWork
            && maximumDepth == options.maximumSubdivisionDepth
            && maximumSourceDepth == options.maximumSourceDepth
            && maximumAlgebraicDepth == options.maximumAlgebraicDepth
            && maximumCumulativeStorageBytes == options.maximumCumulativeStorageBytes
    }

    package func charge(depth: Int = 0) throws {
        try Task.checkCancellation()
        guard (0...maximumDepth).contains(depth) else {
            throw failure("Minimum-distance original proof depth exhausted.")
        }
        try state.withLock { state in
            guard state.consumed < maximumWork else {
                throw failure("Minimum-distance shared original operation allowance exhausted.")
            }
            state.consumed += 1
        }
        // The local reservation remains consumed if the composing owner fails.
        // Its callback can reenter without holding this invocation's Mutex.
        try externalWorkAdmission?(depth)
    }

    package func chargeStorageBytes(_ bytes: Int) throws {
        try Task.checkCancellation()
        guard bytes >= 0 else { throw failure("Distance original byte request is negative.") }
        try state.withLock { state in
            let sum = state.consumedBytes.addingReportingOverflow(bytes)
            guard !sum.overflow,
                maximumCumulativeStorageBytes.map({ sum.partialValue <= $0 }) ?? true else {
                throw failure("Distance shared cumulative original byte allowance exhausted.")
            }
            state.consumedBytes = sum.partialValue
        }
        try externalStorageAdmission?(bytes)
    }

    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded,
            tolerance: tolerance, message: message)
    }
}

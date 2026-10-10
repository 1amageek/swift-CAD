import CADCore
import Synchronization

/// Owns all original integral and trim visits in one moment invocation.
final class VolumeMomentProofBudget: Sendable {
    private struct State: Sendable { var consumed = 0 }
    private let state = Mutex(State())
    private let options: BRepVolumeMomentOptions
    private let tolerance: ModelingTolerance

    init(options: BRepVolumeMomentOptions, tolerance: ModelingTolerance) {
        self.options = options; self.tolerance = tolerance
    }

    var consumedWork: Int { state.withLock { $0.consumed } }

    func charge(_ count: Int = 1, depth: Int = 0) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard count >= 0, (0...options.maximumSubdivisionDepth).contains(depth) else {
            throw failure("Original volume-moment visit or subdivision depth is invalid.")
        }
        try state.withLock { state in
            let next = state.consumed.addingReportingOverflow(count)
            guard !next.overflow, next.partialValue <= options.maximumWork else {
                throw failure("Volume-moment shared original visit allowance exhausted.")
            }
            state.consumed = next.partialValue
        }
    }

    private func failure(_ message: String) -> KernelError {
        KernelError(phase: .topology, code: .resourceLimitExceeded,
            tolerance: tolerance, message: message)
    }
}

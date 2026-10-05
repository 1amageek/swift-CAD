import CADCore
import Synchronization

/// Shared synchronous admission for one original body image preparation.
final class BRepDrawingPreparationUsage: Sendable {
    private struct State: Sendable { var work = 0; var entities = 0 }
    private let state = Mutex(State())
    private let maximumWork: Int
    private let maximumEntities: Int
    private let tolerance: ModelingTolerance

    init(maximumWork: Int, maximumEntities: Int, tolerance: ModelingTolerance) {
        self.maximumWork = maximumWork; self.maximumEntities = maximumEntities; self.tolerance = tolerance
    }
    var consumedWork: Int { state.withLock { $0.work } }
    var retainedEntities: Int { state.withLock { $0.entities } }
    func consume(_ count: Int = 1) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try state.withLock { state in
            guard count >= 0, count <= maximumWork - state.work else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original body image preparation allowance is exhausted.")
            }
            state.work += count
        }
    }
    func retain() throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        try state.withLock { state in
            guard state.work < maximumWork, state.entities < maximumEntities else {
                throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                    message: "Original body image retained entity allowance is exhausted.")
            }
            state.work += 1; state.entities += 1
        }
    }
}

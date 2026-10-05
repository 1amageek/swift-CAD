import CADIR
import Synchronization

/// One cumulative invocation receipt shared by all synchronous placement phases.
final class AssemblyEvaluationUsage: Sendable {
    private struct State: Sendable { var consumedWork: Int }
    private let state: Mutex<State>
    private let maximumWork: Int

    init(maximumWork: Int, consumedWork: Int) throws {
        guard consumedWork >= 0, consumedWork <= maximumWork else {
            throw AssemblyError.resourceLimitExceeded("assembly invocation admission")
        }
        self.maximumWork = maximumWork
        self.state = Mutex(State(consumedWork: consumedWork))
    }
    var consumedWork: Int { state.withLock { $0.consumedWork } }
    var remainingWork: Int { state.withLock { maximumWork - $0.consumedWork } }
    func consume(_ count: Int = 1) throws {
        try Task.checkCancellation()
        try state.withLock { state in
            guard count >= 0, count <= maximumWork - state.consumedWork else {
                throw AssemblyError.resourceLimitExceeded("assembly cumulative work/storage")
            }
            state.consumedWork += count
        }
    }
}

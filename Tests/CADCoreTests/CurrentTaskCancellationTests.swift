import Testing
@testable import CADCore

@Suite("Current task cancellation")
struct CurrentTaskCancellationTests {
    @Test(.timeLimit(.minutes(1)))
    func uncancelledTaskReturnsNormally() async throws {
        let checker = CurrentTaskCancellationChecker()
        let task = Task { () throws -> Bool in
            try checker.checkCancellation()
            return true
        }

        #expect(try await task.value)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancelledTaskPropagatesTypedCancellation() async throws {
        let checker = CurrentTaskCancellationChecker()
        let task = Task { () throws -> Never in
            while true {
                try checker.checkCancellation()
                await Task.yield()
            }
        }
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("A cancelled task completed without CancellationError")
        } catch is CancellationError {
            // The checker preserves the standard cancellation failure.
        }
    }
}

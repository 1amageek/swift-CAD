public struct CurrentTaskCancellationChecker: CurrentTaskCancellationChecking, Sendable {
    public init() {}

    public func checkCancellation() throws(CancellationError) {
        if Task<Never, Never>.isCancelled {
            throw CancellationError()
        }
    }
}

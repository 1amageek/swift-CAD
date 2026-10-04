public protocol CurrentTaskCancellationChecking: Sendable {
    func checkCancellation() throws(CancellationError)
}

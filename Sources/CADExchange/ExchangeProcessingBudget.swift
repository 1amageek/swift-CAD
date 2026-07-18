import CADCore

struct ExchangeProcessingBudget: Sendable {
    private let clock: ContinuousClock
    private let deadline: ContinuousClock.Instant

    init(maximumDuration: Duration) {
        let clock = ContinuousClock()
        self.clock = clock
        self.deadline = clock.now.advanced(by: maximumDuration)
    }

    func check(format: ExchangeFileFormat) throws {
        guard clock.now < deadline else {
            throw KernelError(
                phase: .exchange,
                code: .resourceLimitExceeded,
                tolerance: nil,
                message: "\(format.rawValue.uppercased()) processing exceeded the configured time limit."
            )
        }
    }
}

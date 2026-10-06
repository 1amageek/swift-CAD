import CADCore
import Synchronization

/// Shared references never detach an invocation's counters or original deadline.
final class SharedExchangeResourceAccountant: Sendable {
    let limits: ExchangeResourceLimits
    let format: ExchangeFileFormat
    let budget: ExchangeProcessingBudget
    private let state: Mutex<ExchangeResourceAccountant>

    init(limits: ExchangeResourceLimits, format: ExchangeFileFormat, processingBudget: ExchangeProcessingBudget? = nil) throws {
        let original = try ExchangeResourceAccountant(limits: limits, format: format, processingBudget: processingBudget)
        self.limits = original.limits
        self.format = original.format
        budget = original.budget
        state = Mutex(original)
    }

    var entityCount: Int { state.withLock { $0.entityCount } }
    var iterationCount: Int { state.withLock { $0.iterationCount } }
    var byteCount: Int { state.withLock { $0.byteCount } }
    func snapshot() -> ExchangeResourceAccountant { state.withLock { $0 } }

    func charge(entities: Int = 0, work: Int = 0, bytes: Int = 0) throws {
        try checkTime()
        try state.withLock { current in
            // Commit all counters together only after every ceiling admits the update.
            var candidate = current
            try candidate.recordEntities(entities)
            try candidate.recordIterations(work)
            try candidate.recordBytes(bytes)
            current = candidate
        }
    }

    func recordEntities(_ count: Int = 1) throws { try charge(entities: count) }
    func recordIterations(_ count: Int = 1) throws { try charge(work: count) }
    func recordBytes(_ count: Int, label: String = "processed") throws {
        try checkTime()
        try state.withLock { current in
            var candidate = current
            try candidate.recordBytes(count, label: label)
            current = candidate
        }
    }
    func validateInputByteCount(_ count: Int) throws {
        try checkTime()
        guard count >= 0, count <= limits.maximumBytes else {
            throw exchangeResourceLimitError(format: format, detail: "input exceeds the configured byte limit.")
        }
    }
    func validateNestingDepth(_ depth: Int) throws {
        guard depth >= 0, depth <= limits.maximumNesting else {
            throw exchangeResourceLimitError(format: format, detail: "input exceeds the configured nesting limit.")
        }
    }
    func checkTime() throws { try budget.check(format: format) }
}

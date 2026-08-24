import CADCore

struct ExchangeResourceAccountant: Sendable {
    let limits: ExchangeResourceLimits
    let format: ExchangeFileFormat
    let budget: ExchangeProcessingBudget

    private(set) var entityCount = 0
    private(set) var iterationCount = 0

    init(limits: ExchangeResourceLimits, format: ExchangeFileFormat) throws {
        try limits.validate()
        self.limits = limits
        self.format = format
        budget = ExchangeProcessingBudget(maximumDuration: limits.maximumProcessingDuration)
    }

    func validateInputByteCount(_ byteCount: Int) throws {
        try budget.check(format: format)
        guard byteCount <= limits.maximumBytes else {
            throw resourceError("input exceeds the configured byte limit.")
        }
    }

    mutating func recordEntities(_ count: Int = 1) throws {
        entityCount = try adding(count, to: entityCount, label: "entity")
        guard entityCount <= limits.maximumEntities else {
            throw resourceError("processing exceeds the configured entity limit.")
        }
    }

    mutating func recordIterations(_ count: Int = 1) throws {
        iterationCount = try adding(count, to: iterationCount, label: "iteration")
        guard iterationCount <= limits.maximumIterations else {
            throw resourceError("processing exceeds the configured iteration limit.")
        }
        if iterationCount.isMultiple(of: 1_024) {
            try budget.check(format: format)
        }
    }

    func validateNestingDepth(_ depth: Int) throws {
        guard depth <= limits.maximumNesting else {
            throw resourceError("input exceeds the configured nesting limit.")
        }
    }

    func checkTime() throws {
        try budget.check(format: format)
    }

    private func adding(_ value: Int, to total: Int, label: String) throws -> Int {
        guard value >= 0 else {
            throw resourceError("\(label) accounting received a negative value.")
        }
        let addition = total.addingReportingOverflow(value)
        guard !addition.overflow else {
            throw resourceError("\(label) accounting exceeds the platform integer range.")
        }
        return addition.partialValue
    }

    private func resourceError(_ detail: String) -> KernelError {
        exchangeResourceLimitError(format: format, detail: detail)
    }
}

func exchangeResourceLimitError(
    format: ExchangeFileFormat,
    detail: String
) -> KernelError {
    KernelError(
        phase: .exchange,
        code: .resourceLimitExceeded,
        tolerance: nil,
        message: "\(format.displayName) \(detail)"
    )
}

final class ExchangeBoundedByteSink: ByteSink {
    private let downstream: any ByteSink
    private let maximumBytes: Int
    private let format: ExchangeFileFormat
    private let budget: ExchangeProcessingBudget
    private var byteCount = 0

    init(
        downstream: any ByteSink,
        limits: ExchangeResourceLimits,
        format: ExchangeFileFormat
    ) throws {
        try limits.validate()
        self.downstream = downstream
        maximumBytes = limits.maximumBytes
        self.format = format
        budget = ExchangeProcessingBudget(maximumDuration: limits.maximumProcessingDuration)
    }

    func write(_ bytes: UnsafeRawBufferPointer) throws {
        try budget.check(format: format)
        let addition = byteCount.addingReportingOverflow(bytes.count)
        guard !addition.overflow, addition.partialValue <= maximumBytes else {
            throw exchangeResourceLimitError(
                format: format,
                detail: "output exceeds the configured byte limit."
            )
        }
        try downstream.write(bytes)
        byteCount = addition.partialValue
    }
}

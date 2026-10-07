func exactScalarCount(_ a: Int, _ b: Int, multiply: Bool = false) throws(ExactScalarFailure) -> Int {
    let result = multiply ? a.multipliedReportingOverflow(by: b) : a.addingReportingOverflow(b)
    guard a >= 0, b >= 0, !result.overflow else { throw .countOverflow }
    return result.partialValue
}

func exactScalarBackendFailure(_ message: String) -> ExactScalarFailure { .invalidEvidence }

func exactScalarTaskCheckpoint() throws(CancellationError) {
    if Task<Never, Never>.isCancelled { throw CancellationError() }
}

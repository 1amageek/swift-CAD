import CADCore

func rationalAlgebraFailure(_ message: String) -> KernelError {
    KernelError(phase: .geometry, code: .intersectionFailure, tolerance: nil, message: message)
}

func rationalAlgebraCount(_ a: Int, _ b: Int, multiply: Bool = false) throws -> Int {
    let result = multiply ? a.multipliedReportingOverflow(by: b) : a.addingReportingOverflow(b)
    guard a >= 0, b >= 0, !result.overflow else {
        throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil,
            message: "Exact source algebra count overflows.")
    }
    return result.partialValue
}

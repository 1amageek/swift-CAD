import CADCore

/// Admission supplied by the invocation owning all exact and interval work.
public protocol RationalAlgebraAdmitting {
    mutating func visitExactCell(depth: Int) throws
    mutating func visitCoefficientCell(depth: Int) throws
    mutating func consumeExactWork(_ count: Int) throws
    mutating func retainExactStorage(_ count: Int) throws
}

public extension RationalAlgebraAdmitting {
    mutating func visitCoefficientCell(depth: Int) throws { try visitExactCell(depth: depth) }
}

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

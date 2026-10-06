import CADCore

/// Borrows the caller's original graph allowance without resetting any counter.
struct BooleanGraphAdmission: Sendable {
    let maximumSpanCount: Int
    let maximumSubdivisionDepth: Int
    let remainingSourceDepth: Int
    let maximumAlgebraicDepth: Int
    let consumeWork: @Sendable (Int) throws -> Void
    let consumeStorage: (@Sendable (Int) throws -> Void)?

    init(maximumSpanCount: Int, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
        consumeWork: @escaping @Sendable (Int) throws -> Void,
        consumeStorage: (@Sendable (Int) throws -> Void)?,
        tolerance: ModelingTolerance, maximumAlgebraicDepth: Int = 32) throws {
        guard maximumSpanCount > 0, maximumSubdivisionDepth >= 0,
              maximumSubdivisionDepth <= 32, remainingSourceDepth >= 0,
              (0...32).contains(maximumAlgebraicDepth) else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance,
                message: "Original graph admission requires positive spans and supported nonnegative depths.")
        }
        self.maximumSpanCount = maximumSpanCount
        self.maximumSubdivisionDepth = maximumSubdivisionDepth
        self.remainingSourceDepth = remainingSourceDepth
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
        self.consumeWork = consumeWork
        self.consumeStorage = consumeStorage
    }

    func step() throws {
        try Task.checkCancellation()
        try consumeWork(0)
    }

    func reserve(count: Int, stride: Int) throws {
        try step()
        let bytes = count.multipliedReportingOverflow(by: stride)
        guard count >= 0, stride >= 0, !bytes.overflow else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded,
                message: "Original graph retained-value byte accounting overflowed.")
        }
        try consumeStorage?(bytes.partialValue)
    }
}

import CADCore

/// Counts all visited selected native cells in one rectangle invocation.
struct OriginalRectangleTessellationBudget: Sendable {
    let maximumCellCount: Int
    private(set) var usedCellCount: Int = 0
    var remainingCellCount: Int { maximumCellCount - usedCellCount }

    init(maximumCellCount: Int, tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        guard (1...262_144).contains(maximumCellCount) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                message: "Original rectangle tessellation requires a ceiling within its original proof budget.")
        }
        self.maximumCellCount = maximumCellCount
    }

    mutating func consume(depth: Int, tolerance: ModelingTolerance) throws {
        try Task.checkCancellation()
        guard depth >= 0, depth <= 32, usedCellCount < maximumCellCount else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                message: "Original rectangle tessellation exhausted its aggregate proof budget.")
        }
        usedCellCount += 1
    }
}

import CADCore

/// Invocation-local proof work shared by original native panels and reference cells.
package struct OriginalTessellationProofUsage: Sendable {
    package let maximumCellCount: Int
    private let consumeWork: (@Sendable (Int) throws -> Void)?
    package private(set) var usedCellCount: Int = 0
    package var remainingCellCount: Int { maximumCellCount - usedCellCount }

    package init() {
        maximumCellCount = 262_144
        consumeWork = nil
    }

    /// Lower the same production traversal's ceiling in behavioral resource tests.
    package init(maximumCellCount: Int, tolerance: ModelingTolerance,
        consumeWork: (@Sendable (Int) throws -> Void)? = nil) throws {
        try tolerance.validate()
        guard (1...262_144).contains(maximumCellCount) else {
            throw KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance,
                              message: "Original tessellation requires a cell ceiling within its original proof budget.")
        }
        self.maximumCellCount = maximumCellCount
        self.consumeWork = consumeWork
    }

    package mutating func consume(depth: Int, tolerance: ModelingTolerance) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard depth >= 0, depth <= 32 else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original tessellation exhausted its shared proof depth.")
        }
        guard usedCellCount < maximumCellCount else {
            throw KernelError(phase: .geometry, code: .resourceLimitExceeded, tolerance: tolerance,
                              message: "Original tessellation exhausted its shared proof cell budget.")
        }
        try consumeWork?(depth)
        usedCellCount += 1
    }
}

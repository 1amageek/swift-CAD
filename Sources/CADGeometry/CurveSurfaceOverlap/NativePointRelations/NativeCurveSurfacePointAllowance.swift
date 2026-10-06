import CADCore

/// Value-local admission; selected calls forward the composing caller's ledger.
struct NativeCurveSurfacePointAllowance: RationalAlgebraAdmitting {
    let invocation: CurveSurfaceQueryInvocation?
    let maximumAlgebraicDepth: Int
    private var remainingWork: Int
    private var remainingWords: Int
    private var remainingCells: Int

    init(options: CurveSurfaceIntersectionOptions, invocation: CurveSurfaceQueryInvocation?) throws {
        self.invocation = invocation
        maximumAlgebraicDepth = invocation?.maximumAlgebraicDepth ?? 32
        remainingWork = try rationalAlgebraCount(options.maximumSubdivisionCells,
            options.maximumIterations, multiply: true)
        remainingCells = options.maximumSubdivisionCells
        // The cumulative scalar-work allowance supplies cumulative allocation bytes; exact algebra
        // reports its actual UInt32 payload words before each allocation.
        let bytes = try rationalAlgebraCount(remainingWork,
            MemoryLayout<OriginalRationalIntersectionCells.Cell>.stride, multiply: true)
        remainingWords = bytes / MemoryLayout<UInt32>.stride
    }

    mutating func consumeExactWork(_ count: Int) throws {
        try Task.checkCancellation()
        guard count >= 0 else { throw exhausted("Negative native exact work admission.") }
        if let invocation {
            for _ in 0..<count { try invocation.consumeFixedWork() }
        } else {
            guard count <= remainingWork else { throw exhausted("Native point work allowance exhausted.") }
            remainingWork -= count
        }
    }

    mutating func retainExactStorage(_ count: Int) throws {
        try Task.checkCancellation()
        guard count >= 0 else { throw exhausted("Negative native exact storage admission.") }
        let bytes = try rationalAlgebraCount(count, MemoryLayout<UInt32>.stride, multiply: true)
        if let invocation { try invocation.reserve(count: bytes, stride: 1) }
        else {
            guard count <= remainingWords else { throw exhausted("Native point storage allowance exhausted.") }
            remainingWords -= count
        }
    }

    mutating func retainBytes(_ bytes: Int) throws {
        try RationalAlgebraStorage.retainBytes(bytes, usage: &self)
    }

    mutating func visitExactCell(depth: Int) throws {
        try Task.checkCancellation()
        guard depth >= 0, depth <= maximumAlgebraicDepth, remainingCells > 0 else {
            throw exhausted("Native point exact cell or algebraic depth allowance exhausted.")
        }
        remainingCells -= 1
        try consumeExactWork(1)
    }

    mutating func visitCoefficientCell(depth: Int) throws {
        try visitExactCell(depth: depth)
    }

    private func exhausted(_ message: String) -> KernelError {
        .init(phase: .geometry, code: .resourceLimitExceeded, tolerance: nil, message: message)
    }
}

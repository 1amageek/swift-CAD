import CADCore
import CADGeometry

/// Connects exact scalar and UInt32 storage admission to one composing caller.
struct ShapeAffineWordAdmission: RationalAlgebraAdmitting {
    let maximumSubdivisionDepth: Int
    let consumeWork: @Sendable (Int) throws -> Void
    let consumeStorage: (@Sendable (Int) throws -> Void)?

    mutating func visitExactCell(depth: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard depth >= 0 else {
            throw KernelError(phase: .geometry, code: .invalidInput,
                tolerance: nil, message: "Original affine algebra visit has an invalid depth.")
        }
        // Algebraic extension depth is admitted by the retained word constructor.
        // Its work visit is not a structural descendant or a curve subdivision.
        try consumeWork(0)
    }

    mutating func consumeExactWork(_ count: Int) throws {
        guard count >= 0 else { throw invalidStorageCount() }
        for _ in 0..<count { try visitExactCell(depth: 0) }
    }

    mutating func retainExactStorage(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else { throw invalidStorageCount() }
        try retainBytes(bytes.partialValue)
    }

    func retainBytes(_ count: Int) throws {
        try CurrentTaskCancellationChecker().checkCancellation()
        guard count >= 0 else { throw invalidStorageCount() }
        try consumeStorage?(count)
    }

    private func invalidStorageCount() -> KernelError {
        KernelError(phase: .geometry, code: .resourceLimitExceeded,
            tolerance: nil, message: "Original affine image storage count is invalid or overflows.")
    }
}

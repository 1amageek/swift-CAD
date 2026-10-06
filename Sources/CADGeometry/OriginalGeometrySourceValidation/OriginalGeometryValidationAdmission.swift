import CADCore

/// Scoped exact algebra work admission for original geometry source validation.
struct OriginalGeometryValidationAdmission: RationalAlgebraAdmitting {
    let consumeWork: (Int) throws -> Void
    var consumeStorage: ((Int) throws -> Void)? = nil
    let maximumAlgebraicDepth: Int?

    init(consumeWork: @escaping (Int) throws -> Void,
        consumeStorage: ((Int) throws -> Void)? = nil,
        maximumAlgebraicDepth: Int? = nil) {
        self.consumeWork = consumeWork
        self.consumeStorage = consumeStorage
        self.maximumAlgebraicDepth = maximumAlgebraicDepth
    }

    mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0, maximumAlgebraicDepth.map({ (0...32).contains($0) && depth <= $0 }) ?? true else {
            throw GeometryConversionError.resourceLimitExceeded("Original algebra depth exceeds its independent caller ceiling.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        // Immutable construction authority is retained; a selected caller cap
        // remains an additional algebra ceiling, distinct from source depth.
        try consumeWork(0)
    }

    mutating func consumeExactWork(_ count: Int) throws {
        guard count >= 0 else {
            throw GeometryConversionError.invalidInput("Original validation work count must be nonnegative.")
        }
        for _ in 0..<count {
            try CurrentTaskCancellationChecker().checkCancellation()
            try consumeWork(0)
        }
    }

    mutating func visitCoefficientCell(depth: Int) throws {
        // This validation adapter's ceiling is algebraic, never a spatial or
        // source-recursion offset. Both scalar proof domains borrow its ledger.
        try visitExactCell(depth: depth)
    }

    mutating func retainExactStorage(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Original validation word-byte accounting overflowed.")
        }
        try CurrentTaskCancellationChecker().checkCancellation()
        try consumeStorage?(bytes.partialValue)
        // Keep the historical work debit distinct from actual byte admission.
        try consumeExactWork(count)
    }
}

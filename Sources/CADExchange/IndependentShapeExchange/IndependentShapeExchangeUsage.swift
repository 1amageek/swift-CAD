import CADCore
import CADGeometry
import CADIR

/// One operation's cumulative caller allowance, including any parent-paid lexical prefix.
public struct IndependentShapeExchangeUsage: Sendable {
    public let format: ExchangeFileFormat
    public let limits: ExchangeResourceLimits
    public private(set) var consumedEntities: Int
    public private(set) var consumedWork: Int
    public private(set) var consumedBytes: Int
    private let processing: ExchangeProcessingBudget

    public init(limits: ExchangeResourceLimits, format: ExchangeFileFormat = .step, consumedEntities: Int = 0, consumedWork: Int = 0, consumedBytes: Int = 0) throws {
        try limits.validate()
        guard consumedEntities >= 0, consumedEntities <= limits.maximumEntities,
              consumedWork >= 0, consumedWork <= limits.maximumIterations,
              consumedBytes >= 0, consumedBytes <= limits.maximumBytes else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("Invalid paid exchange prefix.")
        }
        self.format = format; self.limits = limits; self.consumedEntities = consumedEntities
        self.consumedWork = consumedWork; self.consumedBytes = consumedBytes
        processing = ExchangeProcessingBudget(maximumDuration: limits.maximumProcessingDuration)
    }
    init(limits: ExchangeResourceLimits, format: ExchangeFileFormat = .step, processing: ExchangeProcessingBudget,
                 consumedEntities: Int, consumedWork: Int, consumedBytes: Int) throws {
        try limits.validate()
        guard consumedEntities >= 0, consumedEntities <= limits.maximumEntities,
              consumedWork >= 0, consumedWork <= limits.maximumIterations,
              consumedBytes >= 0, consumedBytes <= limits.maximumBytes else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("Invalid parent-paid exchange prefix.")
        }
        self.format = format; self.limits = limits; self.processing = processing; self.consumedEntities = consumedEntities
        self.consumedWork = consumedWork; self.consumedBytes = consumedBytes
    }
    public mutating func charge(entities: Int = 0, work: Int = 0, bytes: Int = 0) throws {
        try check()
        let e = try sum(consumedEntities, entities), w = try sum(consumedWork, work), b = try sum(consumedBytes, bytes)
        guard e <= limits.maximumEntities, w <= limits.maximumIterations, b <= limits.maximumBytes else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("Independent exchange cumulative caller ceiling.")
        }
        consumedEntities = e; consumedWork = w; consumedBytes = b
    }
    public func check() throws { try CurrentTaskCancellationChecker().checkCancellation(); try processing.check(format: format) }
    /// Pays the parent's actual source traversal without minting a reusable validation receipt.
    mutating func validateDocument(_ document:CADDocument,tolerance:ModelingTolerance) throws {
        let records = limits.maximumEntities-consumedEntities, work = limits.maximumIterations-consumedWork
        guard records > 0, work > 0 else { throw IndependentShapeExchangeError.resourceLimitExceeded("No document source-validation allowance.") }
        let deadline = self
        let accounting = try document.validate(tolerance:tolerance,
            independentShapeLimits:.init(maximumRecords:records,maximumTextBytes:limits.maximumBytes-consumedBytes,
                maximumDepth:limits.maximumNesting,maximumWork:work,maximumCurveSubdivisionDepth:limits.maximumCurveSubdivisionDepth,maximumAlgebraicDepth:limits.maximumAlgebraicDepth),check:{ try deadline.check() })
        if let accounting { try charge(entities:accounting.consumedRecords,work:accounting.consumedWork,bytes:accounting.consumedTextBytes) }
    }
    private func sum(_ a: Int, _ b: Int) throws -> Int {
        let next = a.addingReportingOverflow(b)
        guard b >= 0, !next.overflow else { throw IndependentShapeExchangeError.resourceLimitExceeded("Independent exchange count overflow.") }
        return next.partialValue
    }
}

// The invocation's original exchange ledger also owns exact gain preparation.
extension IndependentShapeExchangeUsage: RationalAlgebraAdmitting {
    public mutating func visitSourceCell(depth: Int) throws {
        guard depth >= 0, depth <= limits.maximumNesting else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("Original source nesting exceeds the exchange allowance.")
        }
        try charge(entities: 1, work: 1)
    }
    public mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0, depth <= limits.maximumAlgebraicDepth else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("Original exact source depth exceeds the exchange allowance.")
        }
        try charge(entities: 1, work: 1)
    }
    public mutating func consumeExactWork(_ count: Int) throws { try charge(work: count) }
    public mutating func retainExactStorage(_ count: Int) throws {
        let size = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !size.overflow else {
            throw IndependentShapeExchangeError.resourceLimitExceeded("Original exact source storage overflows.")
        }
        try charge(bytes: size.partialValue)
    }
}

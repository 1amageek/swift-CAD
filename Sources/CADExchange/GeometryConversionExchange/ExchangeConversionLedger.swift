import CADGeometry

/// One invocation owner shared by bounded source preparation and final certification.
final class ExchangeConversionLedger: Sendable {
    private let resources: SharedExchangeResourceAccountant
    private let originalBudget: OriginalQueryBudget

    init(limits: ExchangeResourceLimits, format: ExchangeFileFormat) throws {
        let owner = try SharedExchangeResourceAccountant(limits: limits, format: format, cellVisitRecords: 0)
        resources = owner
        originalBudget = owner.originalBudget
    }
    func charge(entities: Int = 0, work: Int = 0, bytes: Int = 0,
        using execution: inout OriginalQueryExecution) throws {
        guard execution.budget === originalBudget else {
            throw GeometryConversionError.invalidInput("Conversion requires its original invocation owner.")
        }
        try execution.chargeSource(records: entities, work: work, storageBytes: bytes)
    }
    func snapshot() -> ExchangeResourceAccountant { resources.snapshot() }
    func execution() throws -> OriginalQueryExecution {
        try resources.checkTime()
        let limits = resources.limits
        return try OriginalQueryExecution(budget: originalBudget,
            limits: .init(maximumValueDepth: limits.maximumAlgebraicDepth,
                maximumCoefficientDepth: limits.maximumAlgebraicDepth,
                remainingSourceDepth: limits.maximumNesting,
                maximumSubdivisionDepth: limits.maximumCurveSubdivisionDepth,
                maximumSpans: limits.maximumEntities))
    }
    func remainingLimits() throws -> ExchangeResourceLimits {
        let s = snapshot(), l = s.limits
        let remaining = ExchangeResourceLimits(maximumBytes: l.maximumBytes - s.byteCount,
            maximumEntities: l.maximumEntities - s.entityCount, maximumNesting: l.maximumNesting,
            maximumIterations: l.maximumIterations - s.iterationCount,
            maximumProcessingDuration: l.maximumProcessingDuration,
            maximumCurveSubdivisionDepth: l.maximumCurveSubdivisionDepth,
            maximumAlgebraicDepth: l.maximumAlgebraicDepth)
        try remaining.validate(); return remaining
    }
}

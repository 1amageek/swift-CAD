import CADGeometry

/// One invocation owner shared by bounded source preparation and final certification.
final class ExchangeConversionLedger: Sendable {
    private let resources: SharedExchangeResourceAccountant
    private let retainedAdmission: GeometryConversionAdmission

    init(limits: ExchangeResourceLimits, format: ExchangeFileFormat) throws {
        let owner = try SharedExchangeResourceAccountant(limits: limits, format: format)
        resources = owner
        retainedAdmission = try GeometryConversionAdmission(maximumSpanCount: limits.maximumEntities,
            maximumSubdivisionDepth: limits.maximumCurveSubdivisionDepth,
            remainingSourceDepth: limits.maximumNesting,
            consumeWork: { try owner.charge(work: $0) },
            consumeStorage: { try owner.charge(bytes: $0) },
            maximumAlgebraicDepth: limits.maximumAlgebraicDepth)
    }
    func charge(entities: Int = 0, work: Int = 0, bytes: Int = 0) throws {
        try resources.charge(entities: entities, work: work, bytes: bytes)
    }
    func snapshot() -> ExchangeResourceAccountant { resources.snapshot() }
    func admission() throws -> GeometryConversionAdmission {
        try resources.checkTime()
        return retainedAdmission
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

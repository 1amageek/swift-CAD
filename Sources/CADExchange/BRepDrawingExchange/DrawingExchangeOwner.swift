import CADCore
import CADGeometry

/// The immutable root of one complete drawing invocation.
public final class DrawingExchangeOwner: Sendable {
    let resources: SharedExchangeResourceAccountant
    public var maximumBytes: Int { resources.limits.maximumBytes }
    public var maximumWork: Int { resources.limits.maximumIterations }
    public var maximumNesting: Int { resources.limits.maximumNesting }
    public var maximumCurveSubdivisionDepth: Int { resources.limits.maximumCurveSubdivisionDepth }
    public var maximumAlgebraicDepth: Int { resources.limits.maximumAlgebraicDepth }
    public var consumedEntities: Int { resources.entityCount }
    public var consumedWork: Int { resources.iterationCount }
    public var consumedBytes: Int { resources.byteCount }

    public init(limits: ExchangeResourceLimits = .standard, format: ExchangeFileFormat) throws {
        guard [.dxf, .svg, .pdf].contains(format) else { throw ImportError.unsupportedFormat(format.displayName) }
        resources = try .init(limits: limits, format: format)
    }
    init(resources: SharedExchangeResourceAccountant) { self.resources = resources }

    public func execution() throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: resources.originalBudget, limits: try .init(
            maximumValueDepth: max(maximumAlgebraicDepth, maximumCurveSubdivisionDepth), maximumCoefficientDepth: maximumAlgebraicDepth,
            maximumCells: resources.limits.maximumEntities, remainingSourceDepth: maximumNesting,
            maximumTransportDepth: maximumNesting, maximumSubdivisionDepth: maximumCurveSubdivisionDepth,
            maximumSpans: resources.limits.maximumEntities))
    }
    public func charge(entities: Int = 0, work: Int = 0, bytes: Int = 0) throws {
        try resources.charge(entities: entities, work: work, bytes: bytes)
    }
    public func sharesAccountingOwner(with other: DrawingExchangeOwner) -> Bool { resources === other.resources }
    public func check() throws { try resources.checkTime() }
    func validateExecution(_ execution: borrowing OriginalQueryExecution) throws {
        guard execution.budget === resources.originalBudget else {
            throw ExportError.invalidMesh("Drawing operation requires its original invocation execution.")
        }
    }
}

import CADCore
import CADGeometry

/// A complete drawing invocation's cumulative caller allowance.
public struct DrawingExchangeUsage: Sendable {
    var resources: SharedExchangeResourceAccountant
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

    /// Escaping preparation callbacks retain this invocation's live counter owner.
    public var preparationWorkCallback: @Sendable (Int) throws -> Void {
        let owner = resources
        return { try owner.charge(work: $0) }
    }
    /// Storage counts are bytes, matching original contour preparation.
    public var preparationStorageCallback: @Sendable (Int) throws -> Void {
        let owner = resources
        return { try owner.charge(bytes: $0) }
    }
    public mutating func charge(entities: Int = 0, work: Int = 0, bytes: Int = 0) throws {
        try resources.charge(entities: entities, work: work, bytes: bytes)
    }
    public func sharesAccountingOwner(with other: DrawingExchangeUsage) -> Bool { resources === other.resources }
    public func check() throws { try resources.checkTime() }
}

// Exact glyph conversion shares the original invocation's cell/work/storage allowance.
extension DrawingExchangeUsage: RationalAlgebraAdmitting {
    public mutating func visitExactCell(depth: Int) throws {
        guard depth >= 0, depth <= resources.limits.maximumAlgebraicDepth else {
            throw exchangeResourceLimitError(format: resources.format, detail: "exact drawing algebra depth exceeds its caller allowance")
        }
        try charge(entities: 1, work: 1)
    }
    public mutating func consumeExactWork(_ count: Int) throws { try charge(work: count) }
    public mutating func retainExactStorage(_ count: Int) throws {
        let bytes = count.multipliedReportingOverflow(by: MemoryLayout<UInt32>.stride)
        guard count >= 0, !bytes.overflow else { throw exchangeResourceLimitError(format: resources.format, detail: "exact glyph storage overflows") }
        try charge(bytes: bytes.partialValue)
    }
}

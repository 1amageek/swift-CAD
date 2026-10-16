import CADCore

public struct NativeSurfaceConversionSource: GeometrySurfaceConversionSource {
    public let surface: Surface3D
    private enum EnclosureStorage: Sendable {
        case originalPolynomialRuled(OriginalPolynomialRuledConversionSource)
        case originalNative(PreparedSurfaceDifferentialEncloser)
    }
    private let prepared: EnclosureStorage
    private let receipt: OriginalGeometryPreparationReceipt
    private let receiptLimits: OriginalQueryExecutionLimits

    public init(_ surface: Surface3D, tolerance: ModelingTolerance) throws {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try OriginalQueryExecutionLimits(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        try self.init(surface, tolerance: tolerance, using: &execution)
    }

    public init(_ surface: Surface3D, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        self.surface = surface
        receiptLimits = execution.effectiveLimits
        let preparation = try execution.withPreparationScope { execution -> EnclosureStorage in
            if case .procedural(.ruled(let ruled)) = surface,
                OriginalPolynomialRuledConversionSource.accepts(ruled) {
                return .originalPolynomialRuled(try OriginalPolynomialRuledConversionSource(ruled,
                    tolerance: tolerance, using: &execution))
            }
            return .originalNative(try PreparedSurfaceDifferentialEncloser(surface: surface,
                tolerance: tolerance, using: &execution))
        }
        prepared = preparation.result
        receipt = try OriginalGeometryPreparationReceipt(tolerance: tolerance,
            depth: preparation.depth, using: &execution)
    }

    public func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try receipt.admit(tolerance: tolerance, using: &execution)
        guard parameters.u.lower.isFinite, parameters.u.upper.isFinite,
            parameters.v.lower.isFinite, parameters.v.upper.isFinite else {
            throw GeometryConversionError.invalidInput("Bounded surface source requires its original paid preparation and finite box.")
        }
        let bytes = 2.multipliedReportingOverflow(by: MemoryLayout<(ScalarInterval, ParameterDomain)>.stride)
        guard !bytes.overflow else {
            throw GeometryConversionError.resourceLimitExceeded("Bounded surface domain buffer bytes overflow.")
        }
        try execution.retainStorage(bytes: bytes.partialValue)
        for (range, domain) in [(parameters.u, surface.uDomain), (parameters.v, surface.vDomain)] {
            try execution.consumeWork(1)
            if case .closed(let lower, let upper) = domain {
                guard range.lower >= lower, range.upper <= upper else {
                    throw GeometryConversionError.invalidInput("Bounded surface query exceeds the original closed support.")
                }
            }
        }
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> Point3D {
        let box = SurfaceParameterBox(u: try .init(lower: u, upper: u), v: try .init(lower: v, upper: v))
        try validate(over: box, tolerance: tolerance, using: &execution)
        if case .originalPolynomialRuled(let original) = prepared {
            return try original.point(u: u, v: v, tolerance: tolerance, using: &execution)
        }
        guard case .originalNative(let original) = prepared else {
            throw GeometryConversionError.invalidInput("Original surface proposal preparation is unavailable.")
        }
        let bounds = try original.positionBounds(over: box, tolerance: tolerance,
            maximumSpanCount: execution.effectiveLimits.maximumSpans,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            using: &execution)
        let point = Point3D(x: bounds.x.midpoint, y: bounds.y.midpoint, z: bounds.z.midpoint)
        try point.validate()
        return point
    }

    public func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance,
        using execution: inout OriginalQueryExecution) throws -> SurfaceDifferentialEnclosure {
        try validate(over: parameters, tolerance: tolerance, using: &execution)
        if case .originalPolynomialRuled(let original) = prepared {
            return try original.enclosure(over: parameters, tolerance: tolerance, using: &execution)
        }
        guard case .originalNative(let original) = prepared else {
            throw GeometryConversionError.invalidInput("Original surface query preparation is unavailable.")
        }
        return try original.enclosure(over: parameters, tolerance: tolerance,
            maximumSpanCount: execution.effectiveLimits.maximumSpans,
            maximumSubdivisionDepth: execution.effectiveLimits.maximumSubdivisionDepth,
            remainingSourceDepth: execution.effectiveLimits.remainingSourceDepth,
            using: &execution)
    }

    public func validate(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws {
        var execution = reader()
        try validate(over: parameters, tolerance: tolerance, using: &execution)
    }

    public func point(u: Double, v: Double, tolerance: ModelingTolerance) throws -> Point3D {
        var execution = reader()
        return try point(u: u, v: v, tolerance: tolerance, using: &execution)
    }

    public func enclosure(over parameters: SurfaceParameterBox, tolerance: ModelingTolerance) throws -> SurfaceDifferentialEnclosure {
        var execution = reader()
        return try enclosure(over: parameters, tolerance: tolerance, using: &execution)
    }

    private func reader() -> OriginalQueryExecution {
        OriginalQueryExecution(budget: receipt.budget, limits: receiptLimits)
    }
}

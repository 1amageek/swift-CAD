import CADCore

/// The exact UV transfer across one chart-preserving offset relation.
public struct OffsetSurfaceParameterCurveImage: Hashable, Sendable {
    public let source: SurfaceParameterCurve
    public let offset: OffsetSurface3D
    public let isPullback: Bool

    public var sourceSurface: Surface3D {
        isPullback ? .procedural(.offset(offset)) : offset.source
    }

    fileprivate init(
        source: SurfaceParameterCurve,
        offset: OffsetSurface3D,
        isPullback: Bool = false,
        tolerance: ModelingTolerance
    ) throws {
        self.source = source
        self.offset = offset
        self.isPullback = isPullback
        try validate(
            on: targetSurface(tolerance: tolerance),
            tolerance: tolerance
        )
    }

    public func targetSurface(
        tolerance: ModelingTolerance
    ) throws -> Surface3D {
        if isPullback { return offset.source }
        return try offset.exactChartPreservingSurface(tolerance: tolerance)
            ?? .procedural(.offset(offset))
    }

    public func validate(
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try offset.validate(tolerance: tolerance)
        try source.validate(on: sourceSurface, tolerance: tolerance)
        let expectedTarget = try targetSurface(tolerance: tolerance)
        try expectedTarget.validate(tolerance: tolerance)
        guard surface == expectedTarget,
              sourceSurface.uDomain == expectedTarget.uDomain,
              sourceSurface.vDomain == expectedTarget.vDomain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An offset-surface pcurve image requires the destination of its directed offset chart relation."
            )
        }
    }

    // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded source validation and chart
    // lifting consume retained procedural/pullback/zero offset relations here.
    // Legacy materialized analytic targets require exact original radius/origin
    // and normal equality before this port admits those optimized charts.
    package func validateOriginalRelation(on surface: Surface3D,
        tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, consumeWork: () throws -> Void) throws {
        guard remainingSourceDepth > 0, maximumSubdivisionDepth >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original offset chart relation needs caller source admission.")
        }
        try tolerance.validate(); try consumeWork()
        let retainedSource = isPullback ? Surface3D.procedural(.offset(offset)) : offset.source
        let retainedTarget = isPullback || offset.distance == 0
            ? offset.source : .procedural(.offset(offset))
        try retainedSource.validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth - 1,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: { _ in try consumeWork() })
        try source.validateOriginalSource(on: retainedSource, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth - 1,
            maximumSubdivisionDepth: maximumSubdivisionDepth, consumeWork: { _ in try consumeWork() })
        func charge(_ count: Int) throws { for _ in 0..<count { try consumeWork(); try CurrentTaskCancellationChecker().checkCancellation() } }
        try GeometryStructuralComparisonWork.charge(surface: surface, using: charge)
        try GeometryStructuralComparisonWork.charge(surface: retainedTarget, using: charge)
        guard surface == retainedTarget else {
            throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
                message: "Materialized offset chart target lacks an exact original directed source relation.")
        }
        // The procedural offset's original UV law is structurally identical to
        // its source. No rounded analytic substitute supplies this theorem.
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        try source.parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
    }

    public func parameter(
        atCurveParameter parameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        try source.parameter(
            atCurveParameter: parameter,
            curveDomain: curveDomain,
            tolerance: tolerance
        )
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveDifferential {
        try source.differentialGeometry(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
    }

    public func reversed(
        tolerance: ModelingTolerance
    ) throws -> OffsetSurfaceParameterCurveImage {
        try OffsetSurfaceParameterCurveImage(
            source: source.reversed(tolerance: tolerance),
            offset: offset,
            isPullback: isPullback,
            tolerance: tolerance
        )
    }

    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> OffsetSurfaceParameterCurveImage {
        try OffsetSurfaceParameterCurveImage(
            source: source.subcurve(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                tolerance: tolerance
            ),
            offset: offset,
            isPullback: isPullback,
            tolerance: tolerance
        )
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> OffsetSurfaceParameterCurveImage {
        try OffsetSurfaceParameterCurveImage(
            source: source.trimmed(
                from: startParameter,
                to: endParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            ),
            offset: offset,
            isPullback: isPullback,
            tolerance: tolerance
        )
    }

#if !hasFeature(Embedded)
    private enum CodingKeys: String, CodingKey {
        case source
        case offset
        case isPullback
    }
#endif

#if !hasFeature(Embedded)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .offset, .isPullback], in: decoder)
        source = try container.decode(SurfaceParameterCurve.self, forKey: .source)
        offset = try container.decode(OffsetSurface3D.self, forKey: .offset)
        isPullback = container.contains(.isPullback)
            ? try container.decode(Bool.self, forKey: .isPullback) : false
    }
#endif

#if !hasFeature(Embedded)
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(offset, forKey: .offset)
        if isPullback { try container.encode(true, forKey: .isPullback) }
    }
#endif
}

extension OffsetSurface3D {
    /// Pulls UV correspondence off this procedural offset onto its source.
    /// This is a chart transfer, not a geometric offset by the negative distance.
    package func parameterCurvePullback(
        transporting source: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> OffsetSurfaceParameterCurveImage {
        try OffsetSurfaceParameterCurveImage(
            source: source, offset: self, isPullback: true, tolerance: tolerance
        )
    }

    package func parameterCurveImage(
        transporting source: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> OffsetSurfaceParameterCurveImage {
        try OffsetSurfaceParameterCurveImage(
            source: source,
            offset: self,
            tolerance: tolerance
        )
    }
}

#if !hasFeature(Embedded)
extension OffsetSurfaceParameterCurveImage: Codable {}
#endif

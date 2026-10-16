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
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        self.source = source
        self.offset = offset
        self.isPullback = isPullback
        try validate(
            on: targetSurface(tolerance: tolerance, using: &execution),
            tolerance: tolerance
        , using: &execution)
    }

    public func targetSurface(
        tolerance: ModelingTolerance
    ) throws -> Surface3D {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try targetSurface(tolerance: tolerance, using: &execution)
    }


    public func targetSurface(
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> Surface3D {
        try execution.consumeWork(1)
        if isPullback { return offset.source }
        return try offset.exactChartPreservingSurface(tolerance: tolerance, using: &execution)
            ?? .procedural(.offset(offset))
    }

    public func validate(
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try validate(on: surface, tolerance: tolerance, using: &execution)
    }


    public func validate(
        on surface: Surface3D,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws {
        try execution.consumeWork(1)
        try tolerance.validate()
        try offset.validate(tolerance: tolerance, using: &execution)
        try source.validate(on: sourceSurface, tolerance: tolerance, using: &execution)
        let expectedTarget = try targetSurface(tolerance: tolerance, using: &execution)
        try expectedTarget.validate(tolerance: tolerance, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: expectedTarget, using: &execution)
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

    package func validateOriginalRelation(on surface: Surface3D,
        tolerance: ModelingTolerance, remainingSourceDepth: Int,
        maximumSubdivisionDepth: Int, using execution: inout OriginalQueryExecution) throws {
        guard remainingSourceDepth > 0, maximumSubdivisionDepth >= 0 else {
            throw GeometryConversionError.resourceLimitExceeded("Original offset chart relation needs caller source admission.")
        }
        try tolerance.validate(); try execution.consumeWork(1)
        let retainedSource = isPullback ? Surface3D.procedural(.offset(offset)) : offset.source
        let retainedTarget = isPullback || offset.distance == 0
            ? offset.source : .procedural(.offset(offset))
        try retainedSource.validateOriginalSource(tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth - 1,
            maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
        try source.validateOriginalSource(on: retainedSource, tolerance: tolerance,
            remainingSourceDepth: remainingSourceDepth - 1,
            maximumSubdivisionDepth: maximumSubdivisionDepth, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: surface, using: &execution)
        try GeometryStructuralComparisonWork.charge(surface: retainedTarget, using: &execution)
        if surface == retainedTarget {
            try execution.checkpoint()
            return
        }
        if !isPullback, case .plane(let original) = offset.source,
            case .plane(let target) = surface,
            try OriginalPlaneOffsetRelation.proves(source: original, target: target,
                distance: offset.distance, tolerance: tolerance, using: &execution) {
            try execution.checkpoint()
            return
        }
        // FIXME(INCOMPLETE_IMPLEMENTATION): Bounded offset-image validation
        // admits retained offsets and whole-plane displacement identities above.
        // Other materialized analytic families still need their original signed
        // radius/origin and complete UV relation before this caller can accept them.
        throw KernelError(phase: .geometry, code: .unsupportedCapability, tolerance: tolerance,
            message: "Materialized offset chart target lacks an exact original directed source relation.")
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameter(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        return try source.parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
    }

    public func parameter(
        atCurveParameter parameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try self.parameter(atCurveParameter: parameter, curveDomain: curveDomain, tolerance: tolerance, using: &execution)
    }


    public func parameter(
        atCurveParameter parameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameter {
        try execution.consumeWork(1)
        return try source.parameter(
            atCurveParameter: parameter,
            curveDomain: curveDomain,
            tolerance: tolerance
        , using: &execution)
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveDifferential {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try differential(atNormalizedFraction: fraction, tolerance: tolerance, using: &execution)
    }


    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> SurfaceParameterCurveDifferential {
        try execution.consumeWork(1)
        return try source.differentialGeometry(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        , using: &execution)
    }

    public func reversed(
        tolerance: ModelingTolerance
    ) throws -> OffsetSurfaceParameterCurveImage {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try reversed(tolerance: tolerance, using: &execution)
    }


    public func reversed(
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> OffsetSurfaceParameterCurveImage {
        try execution.consumeWork(1)
        return try OffsetSurfaceParameterCurveImage(
            source: source.reversed(tolerance: tolerance, using: &execution),
            offset: offset,
            isPullback: isPullback,
            tolerance: tolerance
        , using: &execution)
    }

    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> OffsetSurfaceParameterCurveImage {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try subcurve(fromNormalizedFraction: lower, toNormalizedFraction: upper, tolerance: tolerance, using: &execution)
    }


    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> OffsetSurfaceParameterCurveImage {
        try execution.consumeWork(1)
        return try OffsetSurfaceParameterCurveImage(
            source: source.subcurve(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                tolerance: tolerance
            , using: &execution),
            offset: offset,
            isPullback: isPullback,
            tolerance: tolerance
        , using: &execution)
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> OffsetSurfaceParameterCurveImage {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try trimmed(from: startParameter, to: endParameter, curveDomain: curveDomain, tolerance: tolerance, using: &execution)
    }


    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> OffsetSurfaceParameterCurveImage {
        try execution.consumeWork(1)
        return try OffsetSurfaceParameterCurveImage(
            source: source.trimmed(
                from: startParameter,
                to: endParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            , using: &execution),
            offset: offset,
            isPullback: isPullback,
            tolerance: tolerance
        , using: &execution)
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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterCurvePullback(transporting: source, tolerance: tolerance, using: &execution)
    }

    package func parameterCurvePullback(
        transporting source: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> OffsetSurfaceParameterCurveImage {
        try execution.consumeWork(1)
        return try OffsetSurfaceParameterCurveImage(
            source: source, offset: self, isPullback: true, tolerance: tolerance
        , using: &execution)
    }

    package func parameterCurveImage(
        transporting source: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    ) throws -> OffsetSurfaceParameterCurveImage {
        var execution = try OriginalQueryExecution.independentGeometry()
        return try parameterCurveImage(transporting: source, tolerance: tolerance, using: &execution)
    }


    package func parameterCurveImage(
        transporting source: SurfaceParameterCurve,
        tolerance: ModelingTolerance
    , using execution: inout OriginalQueryExecution) throws -> OffsetSurfaceParameterCurveImage {
        try execution.consumeWork(1)
        return try OffsetSurfaceParameterCurveImage(
            source: source,
            offset: self,
            tolerance: tolerance
        , using: &execution)
    }
}

#if !hasFeature(Embedded)
extension OffsetSurfaceParameterCurveImage: Codable {}
#endif

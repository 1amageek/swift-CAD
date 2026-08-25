import CADCore

/// The exact image of a source pcurve on the chart-preserving surface produced
/// by one offset operation.
public struct OffsetSurfaceParameterCurveImage: Codable, Hashable, Sendable {
    public let source: SurfaceParameterCurve
    public let offset: OffsetSurface3D

    public var sourceSurface: Surface3D {
        offset.source
    }

    fileprivate init(
        source: SurfaceParameterCurve,
        offset: OffsetSurface3D,
        tolerance: ModelingTolerance
    ) throws {
        self.source = source
        self.offset = offset
        try validate(
            on: targetSurface(tolerance: tolerance),
            tolerance: tolerance
        )
    }

    public func targetSurface(
        tolerance: ModelingTolerance
    ) throws -> Surface3D {
        try offset.exactChartPreservingSurface(tolerance: tolerance)
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
                message: "An offset-surface pcurve image requires the exact chart-preserving surface derived from its offset operation."
            )
        }
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
            tolerance: tolerance
        )
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case offset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys([.source, .offset], in: decoder)
        source = try container.decode(SurfaceParameterCurve.self, forKey: .source)
        offset = try container.decode(OffsetSurface3D.self, forKey: .offset)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(offset, forKey: .offset)
    }
}

extension OffsetSurface3D {
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

import CADCore

/// An exact parameter-space image between two surfaces that share one chart.
public struct SameParameterSurfaceParameterCurve: Codable, Hashable, Sendable {
    public let source: SurfaceParameterCurve
    public let sourceSurface: Surface3D
    public let targetSurface: Surface3D

    public init(
        source: SurfaceParameterCurve,
        sourceSurface: Surface3D,
        targetSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        self.source = source
        self.sourceSurface = sourceSurface
        self.targetSurface = targetSurface
        try validate(on: targetSurface, tolerance: tolerance)
    }

    public func validate(
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        try sourceSurface.validate(tolerance: tolerance)
        try targetSurface.validate(tolerance: tolerance)
        try source.validate(on: sourceSurface, tolerance: tolerance)
        guard surface == targetSurface,
              sourceSurface.uDomain == targetSurface.uDomain,
              sourceSurface.vDomain == targetSurface.vDomain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A same-parameter pcurve image requires its exact target surface and identical source and target parameter domains."
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
    ) throws -> SameParameterSurfaceParameterCurve {
        try SameParameterSurfaceParameterCurve(
            source: source.reversed(tolerance: tolerance),
            sourceSurface: sourceSurface,
            targetSurface: targetSurface,
            tolerance: tolerance
        )
    }

    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> SameParameterSurfaceParameterCurve {
        try SameParameterSurfaceParameterCurve(
            source: source.subcurve(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                tolerance: tolerance
            ),
            sourceSurface: sourceSurface,
            targetSurface: targetSurface,
            tolerance: tolerance
        )
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> SameParameterSurfaceParameterCurve {
        try SameParameterSurfaceParameterCurve(
            source: source.trimmed(
                from: startParameter,
                to: endParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            ),
            sourceSurface: sourceSurface,
            targetSurface: targetSurface,
            tolerance: tolerance
        )
    }
}

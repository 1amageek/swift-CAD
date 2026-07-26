import CADCore
import Foundation

public struct CertifiedAnalyticPairSurfaceParameterCurve: Codable, Hashable, Sendable {
    public let intersection: CertifiedAnalyticAnalyticIntersectionCurve
    public let role: SurfaceIntersectionSurfaceRole
    public let startFraction: Double
    public let endFraction: Double

    init(
        validatedIntersection intersection: CertifiedAnalyticAnalyticIntersectionCurve,
        role: SurfaceIntersectionSurfaceRole,
        startFraction: Double,
        endFraction: Double
    ) {
        self.intersection = intersection
        self.role = role
        self.startFraction = startFraction
        self.endFraction = endFraction
    }

    public init(
        intersection: CertifiedAnalyticAnalyticIntersectionCurve,
        role: SurfaceIntersectionSurfaceRole,
        startFraction: Double = 0.0,
        endFraction: Double = 1.0,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard startFraction.isFinite,
              endFraction.isFinite,
              abs(endFraction - startFraction)
                > Double.leastNonzeroMagnitude,
              abs(endFraction - startFraction) <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(endFraction - startFraction)
        }
        self.intersection = intersection
        self.role = role
        self.startFraction = startFraction
        self.endFraction = endFraction
        try intersection.validate(tolerance: tolerance)
    }

    public func validate(on surface: Surface3D, tolerance: ModelingTolerance) throws {
        try intersection.validate(tolerance: tolerance)
        guard surface == intersection.surface(for: role),
              startFraction.isFinite,
              endFraction.isFinite,
              abs(endFraction - startFraction)
                > Double.leastNonzeroMagnitude,
              abs(endFraction - startFraction) <= 1.0 + tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified analytic-pair pcurve does not belong to the requested surface."
            )
        }
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        let mapped = try mappedFraction(fraction, tolerance: tolerance)
        let point = try intersection.point(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        )
        let result = try intersection.internalParameter(
            for: role,
            atNormalizedFraction: mapped,
            tolerance: tolerance
        )
        let surface = intersection.surface(for: role)
        let reconstructed = try surface.point(
            u: result.u,
            v: result.v,
            tolerance: tolerance
        )
        let residual = (reconstructed - point).length
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A certified analytic-pair pcurve failed exact point reconstruction."
            )
        }
        return result
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveDifferential {
        let mapped = try mappedFraction(fraction, tolerance: tolerance)
        let parameter = try parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let curveDifferential = try intersection.differential(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        )
        let surfaceDifferential = try intersection.surface(for: role).differentialGeometry(
            atU: parameter.u,
            v: parameter.v,
            tolerance: tolerance
        )
        let tangentU = surfaceDifferential.tangentU
        let tangentV = surfaceDifferential.tangentV
        let metricUU = tangentU.dot(tangentU)
        let metricUV = tangentU.dot(tangentV)
        let metricVV = tangentV.dot(tangentV)
        let determinant = metricUU * metricVV - metricUV * metricUV
        let metricScale = max(metricUU * metricVV, Double.leastNonzeroMagnitude)
        let determinantFloor = max(
            tolerance.relative * tolerance.relative,
            Double.ulpOfOne * 1_024.0
        ) * metricScale
        guard determinant.isFinite, determinant > determinantFloor else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "A certified analytic-pair pcurve differential is singular."
            )
        }
        let spatialDerivative = curveDifferential.firstDerivative
        let rightU = tangentU.dot(spatialDerivative)
        let rightV = tangentV.dot(spatialDerivative)
        let derivativeU = (rightU * metricVV - rightV * metricUV) / determinant
        let derivativeV = (rightV * metricUU - rightU * metricUV) / determinant
        let reconstructedDerivative = tangentU * derivativeU + tangentV * derivativeV
        let derivativeScale = max(spatialDerivative.length, 1.0)
        let derivativeResidual = (reconstructedDerivative - spatialDerivative).length
        guard derivativeResidual <= tolerance.relative * derivativeScale else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: derivativeResidual / derivativeScale,
                tolerance: tolerance,
                message: "A certified analytic-pair pcurve failed tangent reconstruction."
            )
        }
        let parameterSecondDerivative = try SurfaceParameterSecondDerivativeSolver().solve(
            surface: surfaceDifferential,
            firstParameterDerivative: Point2D(x: derivativeU, y: derivativeV),
            spatialSecondDerivative: curveDifferential.secondDerivative,
            tolerance: tolerance,
            diagnosticContext: "Certified analytic-pair pcurve"
        )
        let scale = endFraction - startFraction
        return SurfaceParameterCurveDifferential(
            parameter: parameter,
            firstDerivative: Point2D(x: derivativeU * scale, y: derivativeV * scale),
            secondDerivative: Point2D(
                x: parameterSecondDerivative.x * scale * scale,
                y: parameterSecondDerivative.y * scale * scale
            )
        )
    }

    func modelSpaceDifferentialAtCertifiedSupportChartSingularity(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticAnalyticIntersectionCurve.DifferentialGeometry? {
        guard intersection.sphereCylinderCurve != nil
                || intersection.sphereConeCurve != nil
                || intersection.sphereTorusCurve != nil,
              case let .sphere(sphere) = CanonicalAnalyticSurface(
                intersection.surface(for: role)
              ) else {
            return nil
        }
        let parameter = try parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        guard sphere.radius * abs(cos(parameter.v))
                <= tolerance.distance else {
            return nil
        }
        return try modelSpaceDifferential(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
    }

    private func modelSpaceDifferential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticAnalyticIntersectionCurve.DifferentialGeometry {
        let mapped = try mappedFraction(
            fraction,
            tolerance: tolerance
        )
        let source = try intersection.differential(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        )
        let scale = endFraction - startFraction
        return CertifiedAnalyticAnalyticIntersectionCurve
            .DifferentialGeometry(
                position: source.position,
                firstDerivative: source.firstDerivative * scale,
                secondDerivative: source.secondDerivative
                    * (scale * scale)
            )
    }

    public func reversed(
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticPairSurfaceParameterCurve {
        try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: intersection,
            role: role,
            startFraction: endFraction,
            endFraction: startFraction,
            tolerance: tolerance
        )
    }

    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticPairSurfaceParameterCurve {
        try tolerance.validate()
        guard lower.isFinite,
              upper.isFinite,
              lower >= -tolerance.relative,
              upper <= 1.0 + tolerance.relative,
              upper - lower > Double.leastNonzeroMagnitude else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        return try CertifiedAnalyticPairSurfaceParameterCurve(
            intersection: intersection,
            role: role,
            startFraction: interpolate(
                startFraction,
                endFraction,
                fraction: min(max(lower, 0.0), 1.0)
            ),
            endFraction: interpolate(
                startFraction,
                endFraction,
                fraction: min(max(upper, 0.0), 1.0)
            ),
            tolerance: tolerance
        )
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticPairSurfaceParameterCurve {
        try subcurve(
            fromNormalizedFraction: normalizedFraction(
                startParameter,
                domain: curveDomain,
                tolerance: tolerance
            ),
            toNormalizedFraction: normalizedFraction(
                endParameter,
                domain: curveDomain,
                tolerance: tolerance
            ),
            tolerance: tolerance
        )
    }

    private func mappedFraction(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        return canonicalFraction(interpolate(
            startFraction,
            endFraction,
            fraction: min(max(fraction, 0.0), 1.0)
        ), tolerance: tolerance)
    }

    private func normalizedFraction(
        _ parameter: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try domain.validate(tolerance: tolerance)
        guard parameter.isFinite else {
            throw GeometryError.invalidDistance(parameter)
        }
        let globalFraction: Double
        switch domain {
        case let .closed(lower, upper):
            globalFraction = (parameter - lower) / (upper - lower)
        case let .periodic(period):
            globalFraction = parameter / period
        case .unbounded:
            throw GeometryError.invalidDistance(parameter)
        }
        let middle = 0.5 * (startFraction + endFraction)
        let adjusted: Double
        if case .periodic = domain {
            adjusted = globalFraction + round(middle - globalFraction)
        } else {
            adjusted = globalFraction
        }
        let local = (adjusted - startFraction) / (endFraction - startFraction)
        guard local >= -tolerance.relative,
              local <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(parameter)
        }
        return min(max(local, 0.0), 1.0)
    }

    private func canonicalFraction(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ) -> Double {
        if abs(fraction - 1.0) <= tolerance.relative { return 1.0 }
        let remainder = fraction.truncatingRemainder(dividingBy: 1.0)
        return remainder >= 0.0 ? remainder : remainder + 1.0
    }

    private func interpolate(
        _ lower: Double,
        _ upper: Double,
        fraction: Double
    ) -> Double {
        lower + (upper - lower) * fraction
    }

    private enum CodingKeys: String, CodingKey {
        case intersection
        case role
        case startFraction
        case endFraction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.intersection, .role, .startFraction, .endFraction],
            in: decoder
        )
        let intersection = try container.decode(
            CertifiedAnalyticAnalyticIntersectionCurve.self,
            forKey: .intersection
        )
        try self.init(
            intersection: intersection,
            role: container.decode(SurfaceIntersectionSurfaceRole.self, forKey: .role),
            startFraction: container.decode(Double.self, forKey: .startFraction),
            endFraction: container.decode(Double.self, forKey: .endFraction),
            tolerance: intersection.certificationTolerance
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(
            on: intersection.surface(for: role),
            tolerance: intersection.certificationTolerance
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(intersection, forKey: .intersection)
        try container.encode(role, forKey: .role)
        try container.encode(startFraction, forKey: .startFraction)
        try container.encode(endFraction, forKey: .endFraction)
    }
}

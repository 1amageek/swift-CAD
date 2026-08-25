import Foundation
import CADCore

public struct CertifiedImplicitSurfaceParameterCurve: Codable, Hashable, Sendable {
    public let intersection: CertifiedImplicitIntersectionCurve
    public let role: SurfaceIntersectionSurfaceRole
    public let startFraction: Double
    public let endFraction: Double

    init(
        validatedIntersection intersection: CertifiedImplicitIntersectionCurve,
        role: SurfaceIntersectionSurfaceRole,
        startFraction: Double = 0.0,
        endFraction: Double = 1.0
    ) {
        self.intersection = intersection
        self.role = role
        self.startFraction = startFraction
        self.endFraction = endFraction
    }

    public init(
        intersection: CertifiedImplicitIntersectionCurve,
        role: SurfaceIntersectionSurfaceRole,
        startFraction: Double = 0.0,
        endFraction: Double = 1.0,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        // A closed intersection curve represents a seam-crossing span by
        // lifting one fraction past the period, so its fractions may reach 2.
        let upperBound = intersection.isClosed ? 2.0 : 1.0
        guard startFraction.isFinite,
              endFraction.isFinite,
              startFraction >= -tolerance.relative,
              startFraction <= upperBound + tolerance.relative,
              endFraction >= -tolerance.relative,
              endFraction <= upperBound + tolerance.relative,
              abs(endFraction - startFraction) > tolerance.relative,
              abs(endFraction - startFraction) <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(endFraction - startFraction)
        }
        self.intersection = intersection
        self.role = role
        self.startFraction = min(max(startFraction, 0.0), upperBound)
        self.endFraction = min(max(endFraction, 0.0), upperBound)
        try intersection.validate(tolerance: tolerance)
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
            CertifiedImplicitIntersectionCurve.self,
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
        _ = try CertifiedImplicitSurfaceParameterCurve(
            intersection: intersection,
            role: role,
            startFraction: startFraction,
            endFraction: endFraction,
            tolerance: intersection.certificationTolerance
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(intersection, forKey: .intersection)
        try container.encode(role, forKey: .role)
        try container.encode(startFraction, forKey: .startFraction)
        try container.encode(endFraction, forKey: .endFraction)
    }

    public func validate(
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try intersection.validate(tolerance: tolerance)
        let expected = role == .first
            ? intersection.firstSurface
            : intersection.secondSurface
        let exactSurface = try surface.exactChartPreservingRepresentation(
            tolerance: tolerance
        )
        let fractionUpperBound = intersection.isClosed ? 2.0 : 1.0
        guard exactSurface == .bSpline(expected),
              startFraction.isFinite,
              endFraction.isFinite,
              startFraction >= 0.0,
              startFraction <= fractionUpperBound,
              endFraction >= 0.0,
              endFraction <= fractionUpperBound,
              abs(endFraction - startFraction) > tolerance.relative,
              abs(endFraction - startFraction) <= 1.0 + tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified implicit pcurve does not belong to the requested source surface."
            )
        }
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        let intersectionFraction = try mappedFraction(
            fraction,
            tolerance: tolerance
        )
        let pair = try intersection.parameterPair(
            atNormalizedFraction: intersectionFraction,
            tolerance: tolerance
        )
        return role == .first ? pair.first : pair.second
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveDifferential {
        let intersectionFraction = try mappedFraction(
            fraction,
            tolerance: tolerance
        )
        let differential = try intersection.differential(
            atNormalizedFraction: intersectionFraction,
            tolerance: tolerance
        )
        let parameter = role == .first
            ? differential.parameters.first
            : differential.parameters.second
        let derivative = role == .first
            ? differential.firstParameterDerivatives.first
            : differential.firstParameterDerivatives.second
        let secondDerivative = role == .first
            ? differential.secondParameterDerivatives.first
            : differential.secondParameterDerivatives.second
        let scale = endFraction - startFraction
        return SurfaceParameterCurveDifferential(
            parameter: parameter,
            firstDerivative: Point2D(
                x: derivative.u * scale,
                y: derivative.v * scale
            ),
            secondDerivative: Point2D(
                x: secondDerivative.u * scale * scale,
                y: secondDerivative.v * scale * scale
            )
        )
    }

    public func reversed(
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitSurfaceParameterCurve {
        try tolerance.validate()
        return CertifiedImplicitSurfaceParameterCurve(
            validatedIntersection: intersection,
            role: role,
            startFraction: endFraction,
            endFraction: startFraction
        )
    }

    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitSurfaceParameterCurve {
        try tolerance.validate()
        guard lower.isFinite,
              upper.isFinite,
              lower >= -tolerance.relative,
              upper <= 1.0 + tolerance.relative,
              upper - lower > tolerance.relative else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        let clampedLower = min(max(lower, 0.0), 1.0)
        let clampedUpper = min(max(upper, 0.0), 1.0)
        return CertifiedImplicitSurfaceParameterCurve(
            validatedIntersection: intersection,
            role: role,
            startFraction: interpolate(
                startFraction,
                endFraction,
                fraction: clampedLower
            ),
            endFraction: interpolate(
                startFraction,
                endFraction,
                fraction: clampedUpper
            )
        )
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> CertifiedImplicitSurfaceParameterCurve {
        let lower = try normalizedFraction(
            startParameter,
            domain: curveDomain,
            tolerance: tolerance
        )
        var upper = try normalizedFraction(
            endParameter,
            domain: curveDomain,
            tolerance: tolerance
        )
        // On a closed curve a span that crosses the periodic seam wraps its
        // end fraction below its start; lifting it by one period keeps the
        // span monotone.
        if intersection.isClosed,
           case .periodic = curveDomain,
           upper <= lower + tolerance.relative {
            upper += 1.0
        }
        let clampedLower = min(max(lower, 0.0), 1.0)
        return CertifiedImplicitSurfaceParameterCurve(
            validatedIntersection: intersection,
            role: role,
            startFraction: interpolate(
                startFraction,
                endFraction,
                fraction: clampedLower
            ),
            endFraction: interpolate(
                startFraction,
                endFraction,
                fraction: min(max(upper, 0.0), 2.0)
            )
        )
    }

    private func mappedFraction(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        let global = interpolate(
            startFraction,
            endFraction,
            fraction: min(max(fraction, 0.0), 1.0)
        )
        if intersection.isClosed, global > 1.0 {
            return global - 1.0
        }
        return global
    }

    private func normalizedFraction(
        _ parameter: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try domain.validate(tolerance: tolerance)
        switch domain {
        case let .closed(lower, upper):
            guard parameter >= lower - tolerance.relative,
                  parameter <= upper + tolerance.relative else {
                throw GeometryError.invalidDistance(parameter)
            }
            return (parameter - lower) / (upper - lower)
        case let .periodic(period):
            let remainder = parameter.truncatingRemainder(dividingBy: period)
            return (remainder >= 0.0 ? remainder : remainder + period) / period
        case .unbounded:
            throw GeometryError.invalidDistance(parameter)
        }
    }

    private func interpolate(
        _ lower: Double,
        _ upper: Double,
        fraction: Double
    ) -> Double {
        lower + (upper - lower) * fraction
    }
}

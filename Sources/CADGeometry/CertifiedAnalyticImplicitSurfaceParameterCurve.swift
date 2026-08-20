import Foundation
import CADCore

public struct CertifiedAnalyticImplicitSurfaceParameterCurve: Codable, Hashable, Sendable {
    public let intersection: CertifiedAnalyticBSplineIntersectionCurve
    public let startFraction: Double
    public let endFraction: Double

    init(
        validatedIntersection intersection: CertifiedAnalyticBSplineIntersectionCurve,
        startFraction: Double,
        endFraction: Double
    ) {
        self.intersection = intersection
        self.startFraction = startFraction
        self.endFraction = endFraction
    }

    public init(
        intersection: CertifiedAnalyticBSplineIntersectionCurve,
        startFraction: Double = 0.0,
        endFraction: Double = 1.0,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        guard startFraction.isFinite,
              endFraction.isFinite,
              startFraction >= -tolerance.relative,
              startFraction <= 1.0 + tolerance.relative,
              endFraction >= -tolerance.relative,
              endFraction <= 1.0 + tolerance.relative,
              abs(endFraction - startFraction) > tolerance.relative else {
            throw GeometryError.invalidDistance(endFraction - startFraction)
        }
        self.intersection = intersection
        self.startFraction = min(max(startFraction, 0.0), 1.0)
        self.endFraction = min(max(endFraction, 0.0), 1.0)
        try intersection.validate(tolerance: tolerance)
    }

    public func validate(on surface: Surface3D, tolerance: ModelingTolerance) throws {
        try intersection.validate(tolerance: tolerance)
        guard surface == intersection.analyticSurface,
              startFraction.isFinite,
              endFraction.isFinite,
              startFraction >= 0.0,
              startFraction <= 1.0,
              endFraction >= 0.0,
              endFraction <= 1.0,
              abs(endFraction - startFraction) > tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified analytic implicit pcurve does not belong to the requested surface."
            )
        }
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        let mapped = try mappedFraction(fraction, tolerance: tolerance)
        let pair = try intersection.implicitCurve.parameterPair(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        )
        let point = try intersection.implicitCurve.point(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        )
        let internalParameter = intersection.analyticIsFirst ? pair.first : pair.second
        let projection = try intersection.analyticSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        var result = SurfaceParameter(u: projection.u, v: projection.v)
        let canonical = CanonicalAnalyticSurface(intersection.analyticSurface)
        switch canonical {
        case .cylinder, .cone, .sphere:
            result.u = unwrapped(
                result.u,
                near: intersection.periodicSeamOffset + internalParameter.u * Double.pi * 0.5,
                domain: intersection.analyticSurface.uDomain
            )
        case .torus:
            result.u = unwrapped(
                result.u,
                near: intersection.periodicSeamOffset + internalParameter.u * Double.pi * 0.5,
                domain: intersection.analyticSurface.uDomain
            )
            result.v = unwrapped(
                result.v,
                near: intersection.periodicSeamOffset + internalParameter.v * Double.pi * 0.5,
                domain: intersection.analyticSurface.vDomain
            )
        case .plane:
            break
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A certified analytic implicit pcurve has an invalid analytic surface."
            )
        }
        let reconstructed = try intersection.analyticSurface.point(
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
                message: "A certified analytic pcurve failed exact point reconstruction."
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
        let curveDifferential = try intersection.implicitCurve.differential(
            atNormalizedFraction: mapped,
            tolerance: tolerance
        )
        let surfaceDifferential = try intersection.analyticSurface.differentialGeometry(
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
        guard determinant.isFinite,
              determinant > determinantFloor else {
            throw KernelError(
                phase: .geometry,
                code: .singularSystem,
                tolerance: tolerance,
                message: "A certified analytic pcurve differential is singular."
            )
        }
        let spatialDerivative = curveDifferential.firstDerivative
        let rightU = tangentU.dot(spatialDerivative)
        let rightV = tangentV.dot(spatialDerivative)
        let derivativeU = (rightU * metricVV - rightV * metricUV) / determinant
        let derivativeV = (rightV * metricUU - rightU * metricUV) / determinant
        let reconstructedDerivative = tangentU * derivativeU + tangentV * derivativeV
        let derivativeResidual = (reconstructedDerivative - spatialDerivative).length
        let derivativeScale = max(spatialDerivative.length, 1.0)
        guard derivativeResidual <= tolerance.relative * derivativeScale else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: derivativeResidual / derivativeScale,
                tolerance: tolerance,
                message: "A certified analytic pcurve failed tangent reconstruction."
            )
        }
        let parameterSecondDerivative = try SurfaceParameterSecondDerivativeSolver().solve(
            surface: surfaceDifferential,
            firstParameterDerivative: Point2D(x: derivativeU, y: derivativeV),
            spatialSecondDerivative: curveDifferential.secondDerivative,
            tolerance: tolerance,
            diagnosticContext: "Certified analytic pcurve"
        )
        let scale = endFraction - startFraction
        return SurfaceParameterCurveDifferential(
            parameter: parameter,
            firstDerivative: Point2D(
                x: derivativeU * scale,
                y: derivativeV * scale
            ),
            secondDerivative: Point2D(
                x: parameterSecondDerivative.x * scale * scale,
                y: parameterSecondDerivative.y * scale * scale
            )
        )
    }

    public func reversed(
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticImplicitSurfaceParameterCurve {
        try tolerance.validate()
        return CertifiedAnalyticImplicitSurfaceParameterCurve(
            validatedIntersection: intersection,
            startFraction: endFraction,
            endFraction: startFraction
        )
    }

    public func subcurve(
        fromNormalizedFraction lower: Double,
        toNormalizedFraction upper: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticImplicitSurfaceParameterCurve {
        try tolerance.validate()
        guard lower.isFinite,
              upper.isFinite,
              lower >= -tolerance.relative,
              upper <= 1.0 + tolerance.relative,
              upper - lower > tolerance.relative else {
            throw GeometryError.invalidDistance(upper - lower)
        }
        return CertifiedAnalyticImplicitSurfaceParameterCurve(
            validatedIntersection: intersection,
            startFraction: interpolate(
                startFraction,
                endFraction,
                fraction: min(max(lower, 0.0), 1.0)
            ),
            endFraction: interpolate(
                startFraction,
                endFraction,
                fraction: min(max(upper, 0.0), 1.0)
            )
        )
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> CertifiedAnalyticImplicitSurfaceParameterCurve {
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
        return interpolate(
            startFraction,
            endFraction,
            fraction: min(max(fraction, 0.0), 1.0)
        )
    }

    private func normalizedFraction(
        _ parameter: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard case let .closed(lower, upper) = domain,
              parameter.isFinite,
              upper - lower > tolerance.relative else {
            throw GeometryError.invalidDistance(parameter)
        }
        return (parameter - lower) / (upper - lower)
    }

    private func unwrapped(
        _ value: Double,
        near reference: Double,
        domain: ParameterDomain
    ) -> Double {
        guard case let .periodic(period) = domain else { return value }
        return value + ((reference - value) / period).rounded() * period
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
        case startFraction
        case endFraction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.intersection, .startFraction, .endFraction],
            in: decoder
        )
        let intersection = try container.decode(
            CertifiedAnalyticBSplineIntersectionCurve.self,
            forKey: .intersection
        )
        try self.init(
            intersection: intersection,
            startFraction: container.decode(Double.self, forKey: .startFraction),
            endFraction: container.decode(Double.self, forKey: .endFraction),
            tolerance: intersection.implicitCurve.certificationTolerance
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(
            on: intersection.analyticSurface,
            tolerance: intersection.implicitCurve.certificationTolerance
        )
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(intersection, forKey: .intersection)
        try container.encode(startFraction, forKey: .startFraction)
        try container.encode(endFraction, forKey: .endFraction)
    }
}

import Foundation
import CADCore

public struct CertifiedAnalyticBSplineTangencyIntersectionCurve: Codable, Hashable, Sendable {
    public let tangencyCurve: CertifiedQuadraticTangencyIntersectionCurve
    public let analyticSurface: Surface3D
    public let analyticIsFirst: Bool
    public let periodicSeamOffset: Double
    public let analyticSurfaceParameterCurve: SurfaceParameterCurve

    public var curve: Curve3D { tangencyCurve.curve }

    public var boundedSurface: BSplineSurface3D {
        analyticIsFirst ? tangencyCurve.secondSurface : tangencyCurve.firstSurface
    }

    public var firstSurfaceParameterCurve: SurfaceParameterCurve {
        analyticIsFirst
            ? analyticSurfaceParameterCurve
            : tangencyCurve.firstSurfaceParameterCurve
    }

    public var secondSurfaceParameterCurve: SurfaceParameterCurve {
        analyticIsFirst
            ? tangencyCurve.secondSurfaceParameterCurve
            : analyticSurfaceParameterCurve
    }

    public var maximumResidualUpperBound: Double {
        tangencyCurve.maximumResidualUpperBound
    }

    public var certificationTolerance: ModelingTolerance {
        tangencyCurve.certificationTolerance
    }

    public init(
        tangencyCurve: CertifiedQuadraticTangencyIntersectionCurve,
        analyticSurface: Surface3D,
        analyticIsFirst: Bool,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.tangencyCurve = tangencyCurve
        self.analyticSurface = analyticSurface
        self.analyticIsFirst = analyticIsFirst
        self.periodicSeamOffset = periodicSeamOffset
        analyticSurfaceParameterCurve = try Self.buildAnalyticSurfaceParameterCurve(
            tangencyCurve: tangencyCurve,
            analyticSurface: analyticSurface,
            analyticIsFirst: analyticIsFirst,
            periodicSeamOffset: periodicSeamOffset,
            tolerance: tolerance
        )
        try validate(tolerance: tolerance)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try tangencyCurve.validate(tolerance: tolerance)
        try analyticSurface.validate(tolerance: tolerance)
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative,
              periodicSeamOffset.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic B-spline tangency certificate has an invalid tolerance or seam offset."
            )
        }
        let canonical = try Self.canonicalAnalyticSurface(
            analyticSurface,
            tolerance: tolerance
        )
        let rebuilt = try AnalyticSurfaceBSplineBuilder().surface(
            for: canonical,
            boundedBy: boundedSurface,
            periodicSeamOffset: periodicSeamOffset,
            tolerance: certificationTolerance
        )
        let storedAnalytic = analyticIsFirst
            ? tangencyCurve.firstSurface
            : tangencyCurve.secondSurface
        guard rebuilt == storedAnalytic else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "The quadratic tangency surface does not reproduce the exact analytic NURBS conversion."
            )
        }
        let expectedParameterCurve = try Self.buildAnalyticSurfaceParameterCurve(
            tangencyCurve: tangencyCurve,
            analyticSurface: analyticSurface,
            analyticIsFirst: analyticIsFirst,
            periodicSeamOffset: periodicSeamOffset,
            tolerance: tolerance
        )
        guard analyticSurfaceParameterCurve == expectedParameterCurve else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "The stored analytic tangency pcurve is not the certified deterministic reconstruction."
            )
        }
    }

    private static func buildAnalyticSurfaceParameterCurve(
        tangencyCurve: CertifiedQuadraticTangencyIntersectionCurve,
        analyticSurface: Surface3D,
        analyticIsFirst: Bool,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        try tolerance.validate()
        try tangencyCurve.validate(tolerance: tolerance)
        try analyticSurface.validate(tolerance: tolerance)
        guard periodicSeamOffset.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic B-spline tangency requires a finite seam offset."
            )
        }
        let canonical = try canonicalAnalyticSurface(
            analyticSurface,
            tolerance: tolerance
        )
        let lower = try analyticParameter(
            atNormalizedFraction: 0.0,
            tangencyCurve: tangencyCurve,
            analyticSurface: analyticSurface,
            analyticIsFirst: analyticIsFirst,
            periodicSeamOffset: periodicSeamOffset,
            canonical: canonical,
            tolerance: tolerance
        )
        let upper = try analyticParameter(
            atNormalizedFraction: 1.0,
            tangencyCurve: tangencyCurve,
            analyticSurface: analyticSurface,
            analyticIsFirst: analyticIsFirst,
            periodicSeamOffset: periodicSeamOffset,
            canonical: canonical,
            tolerance: tolerance
        )
        let parameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: lower.u, y: lower.v),
                Point2D(x: upper.u, y: upper.v),
            ]
        ))
        try parameterCurve.validate(on: analyticSurface, tolerance: tolerance)
        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: tangencyCurve.curve,
            from: 0.0,
            to: 1.0,
            surface: analyticSurface,
            parameterCurve: parameterCurve,
            options: CurveSurfaceCorrespondenceValidationOptions(
                maximumSubdivisionDepth: 32,
                maximumCellCount: 65_536
            ),
            tolerance: tolerance
        )
        return parameterCurve
    }

    private static func analyticParameter(
        atNormalizedFraction fraction: Double,
        tangencyCurve: CertifiedQuadraticTangencyIntersectionCurve,
        analyticSurface: Surface3D,
        analyticIsFirst: Bool,
        periodicSeamOffset: Double,
        canonical: CanonicalAnalyticSurface,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        let point = try tangencyCurve.curve.point(
            at: fraction,
            tolerance: tolerance
        )
        let internalParameterCurve = analyticIsFirst
            ? tangencyCurve.firstSurfaceParameterCurve
            : tangencyCurve.secondSurfaceParameterCurve
        let internalParameter = try internalParameterCurve.parameter(
            atNormalizedFraction: fraction,
            tolerance: tolerance
        )
        let projection = try analyticSurface.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        guard projection.residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: projection.residual,
                tolerance: tolerance,
                message: "A quadratic tangency point has no certified analytic-surface parameter."
            )
        }
        var result = SurfaceParameter(u: projection.u, v: projection.v)
        switch canonical {
        case .cylinder, .cone, .sphere:
            result.u = unwrapped(
                result.u,
                near: periodicSeamOffset + internalParameter.u * Double.pi * 0.5,
                domain: analyticSurface.uDomain
            )
        case .torus:
            result.u = unwrapped(
                result.u,
                near: periodicSeamOffset + internalParameter.u * Double.pi * 0.5,
                domain: analyticSurface.uDomain
            )
            result.v = unwrapped(
                result.v,
                near: periodicSeamOffset + internalParameter.v * Double.pi * 0.5,
                domain: analyticSurface.vDomain
            )
        case .plane:
            break
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A quadratic tangency certificate requires an exact analytic surface."
            )
        }
        let reconstructed = try analyticSurface.point(
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
                message: "A quadratic tangency pcurve failed exact point reconstruction."
            )
        }
        return result
    }

    private static func canonicalAnalyticSurface(
        _ surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> CanonicalAnalyticSurface {
        let canonical = CanonicalAnalyticSurface(surface)
        switch canonical {
        case .plane, .cylinder, .cone, .sphere, .torus:
            return canonical
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A quadratic tangency certificate requires an exact analytic surface."
            )
        }
    }

    private static func unwrapped(
        _ value: Double,
        near reference: Double,
        domain: ParameterDomain
    ) -> Double {
        guard case let .periodic(period) = domain else { return value }
        return value + ((reference - value) / period).rounded() * period
    }

    private enum CodingKeys: String, CodingKey {
        case tangencyCurve
        case analyticSurface
        case analyticIsFirst
        case periodicSeamOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.tangencyCurve, .analyticSurface, .analyticIsFirst, .periodicSeamOffset],
            in: decoder
        )
        let tangencyCurve = try container.decode(
            CertifiedQuadraticTangencyIntersectionCurve.self,
            forKey: .tangencyCurve
        )
        try self.init(
            tangencyCurve: tangencyCurve,
            analyticSurface: container.decode(Surface3D.self, forKey: .analyticSurface),
            analyticIsFirst: container.decode(Bool.self, forKey: .analyticIsFirst),
            periodicSeamOffset: container.decode(Double.self, forKey: .periodicSeamOffset),
            tolerance: tangencyCurve.certificationTolerance
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tangencyCurve, forKey: .tangencyCurve)
        try container.encode(analyticSurface, forKey: .analyticSurface)
        try container.encode(analyticIsFirst, forKey: .analyticIsFirst)
        try container.encode(periodicSeamOffset, forKey: .periodicSeamOffset)
    }
}

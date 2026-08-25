import Foundation
import CADCore

public struct SurfaceParameter: Codable, Sendable, Hashable {
    public var u: Double
    public var v: Double

    public init(u: Double, v: Double) {
        self.u = u
        self.v = v
    }

    public func validate() throws {
        guard u.isFinite, v.isFinite else {
            throw GeometryError.invalidCoordinate(u.isFinite ? v : u)
        }
    }

    public func isApproximatelyEqual(to other: SurfaceParameter, tolerance: Double) -> Bool {
        hypot(u - other.u, v - other.v) <= tolerance
    }
}

public enum SurfaceParameterBoundary: String, Codable, Sendable, Hashable, CaseIterable {
    case uLower
    case uUpper
    case vLower
    case vUpper
}

public enum SurfaceParameterCurveDirection: String, Codable, Sendable, Hashable {
    case forward
    case reversed
}

public enum SurfaceParameterCurve: Codable, Sendable, Hashable {
    case affine(
        origin: Point2D,
        direction: Point2D,
        startParameter: Double,
        endParameter: Double
    )
    case constantU(u: Double, vStart: Double, vEnd: Double)
    case constantV(v: Double, uStart: Double, uEnd: Double)
    case harmonic(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        startParameter: Double,
        endParameter: Double
    )
    case sphericalGreatCircle(
        cosine: Vector3D,
        sine: Vector3D,
        startParameter: Double,
        endParameter: Double
    )
    case polyline([SurfaceParameter])
    case bSpline(BSplineCurve2D)
    case certifiedImplicit(CertifiedImplicitSurfaceParameterCurve)
    case certifiedAnalyticImplicit(CertifiedAnalyticImplicitSurfaceParameterCurve)
    case certifiedAnalyticPair(CertifiedAnalyticPairSurfaceParameterCurve)
    indirect case projectedAnalytic(ProjectedAnalyticSurfaceParameterCurve)
    indirect case rigidImage(RigidImageSurfaceParameterCurve)
    indirect case offsetSurfaceImage(OffsetSurfaceParameterCurveImage)
    indirect case periodicTranslation(
        base: SurfaceParameterCurve,
        uShift: Double,
        vShift: Double
    )

    public static func boundary(
        _ boundary: SurfaceParameterBoundary,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        let uBounds = try closedBounds(surface.uDomain, tolerance: tolerance)
        let vBounds = try closedBounds(surface.vDomain, tolerance: tolerance)
        switch boundary {
        case .uLower:
            return .constantU(u: uBounds.lower, vStart: vBounds.lower, vEnd: vBounds.upper)
        case .uUpper:
            return .constantU(u: uBounds.upper, vStart: vBounds.lower, vEnd: vBounds.upper)
        case .vLower:
            return .constantV(v: vBounds.lower, uStart: uBounds.lower, uEnd: uBounds.upper)
        case .vUpper:
            return .constantV(v: vBounds.upper, uStart: uBounds.lower, uEnd: uBounds.upper)
        }
    }

    public func validate(
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        switch self {
        case let .affine(origin, direction, startParameter, endParameter):
            let values = [
                origin.x, origin.y, direction.x, direction.y,
                startParameter, endParameter,
            ]
            guard values.allSatisfy(\.isFinite),
                  hypot(direction.x, direction.y) > Double.ulpOfOne,
                  endParameter - startParameter > tolerance.distance else {
                throw GeometryError.invalidDistance(endParameter - startParameter)
            }
            for parameter in [startParameter, endParameter] {
                try validateParameter(
                    affineParameter(origin: origin, direction: direction, parameter: parameter),
                    on: surface,
                    tolerance: tolerance
                )
            }
        case let .constantU(u, vStart, vEnd):
            try validateParameter(SurfaceParameter(u: u, v: vStart), on: surface, tolerance: tolerance)
            try validateParameter(SurfaceParameter(u: u, v: vEnd), on: surface, tolerance: tolerance)
            guard abs(vEnd - vStart) > Double.ulpOfOne else {
                throw GeometryError.invalidDistance(vEnd - vStart)
            }
        case let .constantV(v, uStart, uEnd):
            try validateParameter(SurfaceParameter(u: uStart, v: v), on: surface, tolerance: tolerance)
            try validateParameter(SurfaceParameter(u: uEnd, v: v), on: surface, tolerance: tolerance)
            guard abs(uEnd - uStart) > Double.ulpOfOne else {
                throw GeometryError.invalidDistance(uEnd - uStart)
            }
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            let values = [
                center.x, center.y, cosine.x, cosine.y, sine.x, sine.y,
                startParameter, endParameter,
            ]
            guard values.allSatisfy(\.isFinite),
                  abs(endParameter - startParameter) > tolerance.angle,
                  abs(endParameter - startParameter) <= 2.0 * Double.pi + tolerance.angle else {
                throw GeometryError.invalidDistance(endParameter - startParameter)
            }
            for parameter in harmonicValidationParameters(
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter
            ) {
                try validateParameter(
                    harmonicParameter(
                        center: center,
                        cosine: cosine,
                        sine: sine,
                        parameter: parameter
                    ),
                    on: surface,
                    tolerance: tolerance
                )
            }
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            guard case .analytic(.sphere) = surface else {
                throw GeometryError.invalidDistance(endParameter - startParameter)
            }
            try cosine.validateUnitLength(tolerance: tolerance)
            try sine.validateUnitLength(tolerance: tolerance)
            guard abs(cosine.dot(sine)) <= tolerance.angle,
                  startParameter.isFinite,
                  endParameter.isFinite,
                  abs(endParameter - startParameter) > tolerance.angle,
                  abs(endParameter - startParameter) <= 2.0 * Double.pi + tolerance.angle else {
                throw GeometryError.invalidDistance(endParameter - startParameter)
            }
            for parameter in [startParameter, endParameter] {
                try validateParameter(
                    sphericalParameter(
                        cosine: cosine,
                        sine: sine,
                        parameter: parameter,
                        startParameter: startParameter,
                        endParameter: endParameter
                    ),
                    on: surface,
                    tolerance: tolerance
                )
            }
        case let .polyline(points):
            guard points.count >= 2 else {
                throw GeometryError.invalidDistance(Double(points.count))
            }
            var totalLength = 0.0
            var previous: SurfaceParameter?
            for point in points {
                try validateParameter(point, on: surface, tolerance: tolerance)
                if let previous {
                    totalLength += parameterDistance(from: previous, to: point)
                }
                previous = point
            }
            guard totalLength > Double.ulpOfOne else {
                throw GeometryError.invalidDistance(totalLength)
            }
        case let .bSpline(curve):
            try curve.validate(tolerance: tolerance)
            for controlPoint in curve.controlPoints {
                try validateParameter(
                    SurfaceParameter(u: controlPoint.x, v: controlPoint.y),
                    on: surface,
                    tolerance: tolerance
                )
            }
        case let .certifiedImplicit(curve):
            try curve.validate(on: surface, tolerance: tolerance)
        case let .certifiedAnalyticImplicit(curve):
            try curve.validate(on: surface, tolerance: tolerance)
        case let .certifiedAnalyticPair(curve):
            try curve.validate(on: surface, tolerance: tolerance)
        case let .projectedAnalytic(curve):
            try curve.validate(on: surface, tolerance: tolerance)
        case let .rigidImage(curve):
            try curve.validate(on: surface, tolerance: tolerance)
        case let .offsetSurfaceImage(curve):
            try curve.validate(on: surface, tolerance: tolerance)
        case let .periodicTranslation(base, uShift, vShift):
            try base.validate(on: surface, tolerance: tolerance)
            try validatePeriodicShift(
                uShift,
                domain: surface.uDomain,
                tolerance: tolerance
            )
            try validatePeriodicShift(
                vShift,
                domain: surface.vDomain,
                tolerance: tolerance
            )
        }
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.distance,
              fraction <= 1.0 + tolerance.distance else {
            throw GeometryError.invalidDistance(fraction)
        }
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        switch self {
        case let .affine(origin, direction, startParameter, endParameter):
            return affineParameter(
                origin: origin,
                direction: direction,
                parameter: interpolated(startParameter, endParameter, fraction: clampedFraction)
            )
        case let .constantU(u, vStart, vEnd):
            return SurfaceParameter(u: u, v: interpolated(vStart, vEnd, fraction: clampedFraction))
        case let .constantV(v, uStart, uEnd):
            return SurfaceParameter(u: interpolated(uStart, uEnd, fraction: clampedFraction), v: v)
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return harmonicParameter(
                center: center,
                cosine: cosine,
                sine: sine,
                parameter: interpolated(
                    startParameter,
                    endParameter,
                    fraction: clampedFraction
                )
            )
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return sphericalParameter(
                cosine: cosine,
                sine: sine,
                parameter: interpolated(startParameter, endParameter, fraction: clampedFraction),
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .polyline(points):
            return try polylineParameter(points: points, fraction: clampedFraction)
        case let .bSpline(curve):
            let bounds = try Self.closedBounds(curve.domain, tolerance: tolerance)
            let parameter = interpolated(bounds.lower, bounds.upper, fraction: clampedFraction)
            let point = try curve.pointAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
            return SurfaceParameter(u: point.x, v: point.y)
        case let .certifiedImplicit(curve):
            return try curve.parameter(
                atNormalizedFraction: clampedFraction,
                tolerance: tolerance
            )
        case let .certifiedAnalyticImplicit(curve):
            return try curve.parameter(
                atNormalizedFraction: clampedFraction,
                tolerance: tolerance
            )
        case let .certifiedAnalyticPair(curve):
            return try curve.parameter(
                atNormalizedFraction: clampedFraction,
                tolerance: tolerance
            )
        case let .projectedAnalytic(curve):
            return try curve.parameter(
                atNormalizedFraction: clampedFraction,
                tolerance: tolerance
            )
        case let .rigidImage(curve):
            return try curve.parameter(
                atNormalizedFraction: clampedFraction,
                tolerance: tolerance
            )
        case let .offsetSurfaceImage(curve):
            return try curve.parameter(
                atNormalizedFraction: clampedFraction,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, uShift, vShift):
            let parameter = try base.parameter(
                atNormalizedFraction: clampedFraction,
                tolerance: tolerance
            )
            return SurfaceParameter(
                u: parameter.u + uShift,
                v: parameter.v + vShift
            )
        }
    }

    public func parameter(
        atCurveParameter parameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        try tolerance.validate()
        guard parameter.isFinite else {
            throw GeometryError.invalidDistance(parameter)
        }
        switch self {
        case let .affine(origin, direction, _, _):
            return affineParameter(origin: origin, direction: direction, parameter: parameter)
        case let .harmonic(center, cosine, sine, _, _):
            return harmonicParameter(
                center: center,
                cosine: cosine,
                sine: sine,
                parameter: parameter
            )
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return sphericalParameter(
                cosine: cosine,
                sine: sine,
                parameter: parameter,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .bSpline(curve):
            let pcurveParameter: Double
            if case .periodic = curveDomain {
                let fraction = try normalizedFraction(
                    parameter,
                    domain: curveDomain,
                    tolerance: tolerance
                )
                let bounds = try Self.closedBounds(
                    curve.domain,
                    tolerance: tolerance
                )
                pcurveParameter = interpolated(
                    bounds.lower,
                    bounds.upper,
                    fraction: fraction
                )
            } else {
                pcurveParameter = parameter
            }
            let point = try curve.pointAssumingValid(
                at: pcurveParameter,
                tolerance: tolerance
            )
            return SurfaceParameter(u: point.x, v: point.y)
        case let .certifiedImplicit(curve):
            return try curve.parameter(
                atNormalizedFraction: certifiedLocalFraction(
                    parameter,
                    domain: curveDomain,
                    startFraction: curve.startFraction,
                    endFraction: curve.endFraction,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
        case let .certifiedAnalyticImplicit(curve):
            return try curve.parameter(
                atNormalizedFraction: certifiedLocalFraction(
                    parameter,
                    domain: curveDomain,
                    startFraction: curve.startFraction,
                    endFraction: curve.endFraction,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
        case let .certifiedAnalyticPair(curve):
            return try curve.parameter(
                atNormalizedFraction: certifiedLocalFraction(
                    parameter,
                    domain: curveDomain,
                    startFraction: curve.startFraction,
                    endFraction: curve.endFraction,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
        case let .projectedAnalytic(curve):
            return try curve.parameter(
                atCurveParameter: parameter,
                tolerance: tolerance
            )
        case let .rigidImage(curve):
            return try curve.parameter(
                atNormalizedFraction: normalizedFraction(
                    parameter,
                    domain: curveDomain,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
        case let .offsetSurfaceImage(curve):
            return try curve.parameter(
                atCurveParameter: parameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            )
        case let .periodicTranslation(base, uShift, vShift):
            let result = try base.parameter(
                atCurveParameter: parameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            )
            return SurfaceParameter(
                u: result.u + uShift,
                v: result.v + vShift
            )
        case .constantU, .constantV, .polyline:
            return try self.parameter(
                atNormalizedFraction: normalizedFraction(
                    parameter,
                    domain: curveDomain,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
        }
    }

    public func startParameter(tolerance: ModelingTolerance) throws -> SurfaceParameter {
        try parameter(atNormalizedFraction: 0.0, tolerance: tolerance)
    }

    public func endParameter(tolerance: ModelingTolerance) throws -> SurfaceParameter {
        try parameter(atNormalizedFraction: 1.0, tolerance: tolerance)
    }

    public func reversed(tolerance: ModelingTolerance) throws -> SurfaceParameterCurve {
        try tolerance.validate()
        switch self {
        case let .affine(origin, direction, startParameter, endParameter):
            return .affine(
                origin: Point2D(
                    x: origin.x + direction.x * (startParameter + endParameter),
                    y: origin.y + direction.y * (startParameter + endParameter)
                ),
                direction: Point2D(x: -direction.x, y: -direction.y),
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .constantU(u, vStart, vEnd):
            return .constantU(u: u, vStart: vEnd, vEnd: vStart)
        case let .constantV(v, uStart, uEnd):
            return .constantV(v: v, uStart: uEnd, uEnd: uStart)
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return .harmonic(
                center: center,
                cosine: cosine,
                sine: sine,
                startParameter: endParameter,
                endParameter: startParameter
            )
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return .sphericalGreatCircle(
                cosine: cosine,
                sine: sine,
                startParameter: endParameter,
                endParameter: startParameter
            )
        case let .polyline(points):
            return .polyline(Array(points.reversed()))
        case let .bSpline(curve):
            return .bSpline(try curve.reversed(tolerance: tolerance))
        case let .certifiedImplicit(curve):
            return .certifiedImplicit(try curve.reversed(tolerance: tolerance))
        case let .certifiedAnalyticImplicit(curve):
            return .certifiedAnalyticImplicit(try curve.reversed(tolerance: tolerance))
        case let .certifiedAnalyticPair(curve):
            return .certifiedAnalyticPair(try curve.reversed(tolerance: tolerance))
        case let .projectedAnalytic(curve):
            return .projectedAnalytic(try curve.reversed(tolerance: tolerance))
        case let .rigidImage(curve):
            return .rigidImage(try curve.reversed(tolerance: tolerance))
        case let .offsetSurfaceImage(curve):
            return .offsetSurfaceImage(try curve.reversed(tolerance: tolerance))
        case let .periodicTranslation(base, uShift, vShift):
            return .periodicTranslation(
                base: try base.reversed(tolerance: tolerance),
                uShift: uShift,
                vShift: vShift
            )
        }
    }

    package func materializingPeriodicTranslation() -> SurfaceParameterCurve {
        guard case let .periodicTranslation(base, uShift, vShift) = self else {
            return self
        }
        switch base {
        case let .affine(origin, direction, startParameter, endParameter):
            return .affine(
                origin: Point2D(x: origin.x + uShift, y: origin.y + vShift),
                direction: direction,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .constantU(u, vStart, vEnd):
            return .constantU(
                u: u + uShift,
                vStart: vStart + vShift,
                vEnd: vEnd + vShift
            )
        case let .constantV(v, uStart, uEnd):
            return .constantV(
                v: v + vShift,
                uStart: uStart + uShift,
                uEnd: uEnd + uShift
            )
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return .harmonic(
                center: Point2D(x: center.x + uShift, y: center.y + vShift),
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .polyline(points):
            return .polyline(points.map {
                SurfaceParameter(u: $0.u + uShift, v: $0.v + vShift)
            })
        case let .bSpline(spline):
            return .bSpline(BSplineCurve2D(
                degree: spline.degree,
                knots: spline.knots,
                controlPoints: spline.controlPoints.map {
                    Point2D(x: $0.x + uShift, y: $0.y + vShift)
                },
                weights: spline.weights
            ))
        case let .periodicTranslation(nestedBase, nestedUShift, nestedVShift):
            return SurfaceParameterCurve.periodicTranslation(
                base: nestedBase,
                uShift: uShift + nestedUShift,
                vShift: vShift + nestedVShift
            ).materializingPeriodicTranslation()
        case .sphericalGreatCircle, .certifiedImplicit, .certifiedAnalyticImplicit,
             .certifiedAnalyticPair, .projectedAnalytic, .rigidImage,
             .offsetSurfaceImage:
            return .periodicTranslation(
                base: base,
                uShift: uShift,
                vShift: vShift
            )
        }
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        try tolerance.validate()
        guard startParameter.isFinite,
              endParameter.isFinite,
              endParameter - startParameter > max(tolerance.angle, tolerance.distance),
              try curveDomain.containsSpan(
                  from: startParameter,
                  to: endParameter,
                  tolerance: tolerance
              ) else {
            throw GeometryError.invalidDistance(endParameter - startParameter)
        }
        switch self {
        case let .affine(origin, direction, _, _):
            return .affine(
                origin: origin,
                direction: direction,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .constantU(u, _, _):
            let fractions = try trimFractions(
                from: startParameter,
                to: endParameter,
                domain: curveDomain,
                tolerance: tolerance
            )
            let start = try parameter(
                atNormalizedFraction: fractions.start,
                tolerance: tolerance
            )
            let end = try parameter(
                atNormalizedFraction: fractions.end,
                tolerance: tolerance
            )
            return .constantU(u: u, vStart: start.v, vEnd: end.v)
        case let .constantV(v, _, _):
            let fractions = try trimFractions(
                from: startParameter,
                to: endParameter,
                domain: curveDomain,
                tolerance: tolerance
            )
            let start = try parameter(
                atNormalizedFraction: fractions.start,
                tolerance: tolerance
            )
            let end = try parameter(
                atNormalizedFraction: fractions.end,
                tolerance: tolerance
            )
            return .constantV(v: v, uStart: start.u, uEnd: end.u)
        case let .harmonic(center, cosine, sine, _, _):
            return .harmonic(
                center: center,
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .sphericalGreatCircle(cosine, sine, _, _):
            return .sphericalGreatCircle(
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .polyline(points):
            return try trimmedPolyline(
                points,
                from: startParameter,
                to: endParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            )
        case let .bSpline(curve):
            return .bSpline(try curve.trimmed(
                from: startParameter,
                to: endParameter,
                tolerance: tolerance
            ))
        case let .certifiedImplicit(curve):
            return .certifiedImplicit(try curve.trimmed(
                from: startParameter,
                to: endParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            ))
        case let .certifiedAnalyticImplicit(curve):
            return .certifiedAnalyticImplicit(try curve.trimmed(
                from: startParameter,
                to: endParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            ))
        case let .certifiedAnalyticPair(curve):
            return .certifiedAnalyticPair(try curve.trimmed(
                from: startParameter,
                to: endParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            ))
        case let .projectedAnalytic(curve):
            return .projectedAnalytic(try curve.trimmed(
                from: startParameter,
                to: endParameter,
                tolerance: tolerance
            ))
        case let .rigidImage(curve):
            let lower = try normalizedFraction(
                startParameter,
                domain: curveDomain,
                tolerance: tolerance
            )
            let upper = try normalizedFraction(
                endParameter,
                domain: curveDomain,
                tolerance: tolerance
            )
            return .rigidImage(try curve.subcurve(
                fromNormalizedFraction: lower,
                toNormalizedFraction: upper,
                tolerance: tolerance
            ))
        case let .offsetSurfaceImage(curve):
            return .offsetSurfaceImage(try curve.trimmed(
                from: startParameter,
                to: endParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            ))
        case let .periodicTranslation(base, uShift, vShift):
            return .periodicTranslation(
                base: try base.trimmed(
                    from: startParameter,
                    to: endParameter,
                    curveDomain: curveDomain,
                    tolerance: tolerance
                ),
                uShift: uShift,
                vShift: vShift
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case origin
        case direction
        case u
        case v
        case uStart
        case uEnd
        case vStart
        case vEnd
        case center
        case cosine
        case sine
        case startParameter
        case endParameter
        case points
        case bSpline
        case certifiedImplicit
        case certifiedAnalyticImplicit
        case certifiedAnalyticPair
        case sphericalGreatCircle
        case projectedAnalytic
        case rigidImage
        case offsetSurfaceImage
        case base
        case uShift
        case vShift
    }

    private enum Kind: String, Codable {
        case affine
        case constantU
        case constantV
        case harmonic
        case polyline
        case bSpline
        case certifiedImplicit
        case certifiedAnalyticImplicit
        case certifiedAnalyticPair
        case sphericalGreatCircle
        case projectedAnalytic
        case rigidImage
        case offsetSurfaceImage
        case periodicTranslation
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .affine:
            try container.validateOnlyExpectedKeys(
                [.kind, .origin, .direction, .startParameter, .endParameter],
                in: decoder
            )
            self = .affine(
                origin: try container.decode(Point2D.self, forKey: .origin),
                direction: try container.decode(Point2D.self, forKey: .direction),
                startParameter: try container.decode(Double.self, forKey: .startParameter),
                endParameter: try container.decode(Double.self, forKey: .endParameter)
            )
        case .constantU:
            try container.validateOnlyExpectedKeys([.kind, .u, .vStart, .vEnd], in: decoder)
            self = .constantU(
                u: try container.decode(Double.self, forKey: .u),
                vStart: try container.decode(Double.self, forKey: .vStart),
                vEnd: try container.decode(Double.self, forKey: .vEnd)
            )
        case .constantV:
            try container.validateOnlyExpectedKeys([.kind, .v, .uStart, .uEnd], in: decoder)
            self = .constantV(
                v: try container.decode(Double.self, forKey: .v),
                uStart: try container.decode(Double.self, forKey: .uStart),
                uEnd: try container.decode(Double.self, forKey: .uEnd)
            )
        case .harmonic:
            try container.validateOnlyExpectedKeys(
                [.kind, .center, .cosine, .sine, .startParameter, .endParameter],
                in: decoder
            )
            self = .harmonic(
                center: try container.decode(Point2D.self, forKey: .center),
                cosine: try container.decode(Point2D.self, forKey: .cosine),
                sine: try container.decode(Point2D.self, forKey: .sine),
                startParameter: try container.decode(Double.self, forKey: .startParameter),
                endParameter: try container.decode(Double.self, forKey: .endParameter)
            )
        case .polyline:
            try container.validateOnlyExpectedKeys([.kind, .points], in: decoder)
            self = .polyline(try container.decode([SurfaceParameter].self, forKey: .points))
        case .bSpline:
            try container.validateOnlyExpectedKeys([.kind, .bSpline], in: decoder)
            self = .bSpline(try container.decode(BSplineCurve2D.self, forKey: .bSpline))
        case .certifiedImplicit:
            try container.validateOnlyExpectedKeys([.kind, .certifiedImplicit], in: decoder)
            self = .certifiedImplicit(
                try container.decode(
                    CertifiedImplicitSurfaceParameterCurve.self,
                    forKey: .certifiedImplicit
                )
            )
        case .certifiedAnalyticImplicit:
            try container.validateOnlyExpectedKeys(
                [.kind, .certifiedAnalyticImplicit],
                in: decoder
            )
            self = .certifiedAnalyticImplicit(
                try container.decode(
                    CertifiedAnalyticImplicitSurfaceParameterCurve.self,
                    forKey: .certifiedAnalyticImplicit
                )
            )
        case .certifiedAnalyticPair:
            try container.validateOnlyExpectedKeys(
                [.kind, .certifiedAnalyticPair],
                in: decoder
            )
            self = .certifiedAnalyticPair(
                try container.decode(
                    CertifiedAnalyticPairSurfaceParameterCurve.self,
                    forKey: .certifiedAnalyticPair
                )
            )
        case .sphericalGreatCircle:
            try container.validateOnlyExpectedKeys(
                [.kind, .cosine, .sine, .startParameter, .endParameter],
                in: decoder
            )
            self = .sphericalGreatCircle(
                cosine: try container.decode(Vector3D.self, forKey: .cosine),
                sine: try container.decode(Vector3D.self, forKey: .sine),
                startParameter: try container.decode(Double.self, forKey: .startParameter),
                endParameter: try container.decode(Double.self, forKey: .endParameter)
            )
        case .projectedAnalytic:
            try container.validateOnlyExpectedKeys([.kind, .projectedAnalytic], in: decoder)
            self = .projectedAnalytic(try container.decode(
                ProjectedAnalyticSurfaceParameterCurve.self,
                forKey: .projectedAnalytic
            ))
        case .rigidImage:
            try container.validateOnlyExpectedKeys([.kind, .rigidImage], in: decoder)
            self = .rigidImage(try container.decode(
                RigidImageSurfaceParameterCurve.self,
                forKey: .rigidImage
            ))
        case .offsetSurfaceImage:
            try container.validateOnlyExpectedKeys(
                [.kind, .offsetSurfaceImage],
                in: decoder
            )
            self = .offsetSurfaceImage(try container.decode(
                OffsetSurfaceParameterCurveImage.self,
                forKey: .offsetSurfaceImage
            ))
        case .periodicTranslation:
            try container.validateOnlyExpectedKeys(
                [.kind, .base, .uShift, .vShift],
                in: decoder
            )
            self = .periodicTranslation(
                base: try container.decode(SurfaceParameterCurve.self, forKey: .base),
                uShift: try container.decode(Double.self, forKey: .uShift),
                vShift: try container.decode(Double.self, forKey: .vShift)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .affine(origin, direction, startParameter, endParameter):
            try container.encode(Kind.affine, forKey: .kind)
            try container.encode(origin, forKey: .origin)
            try container.encode(direction, forKey: .direction)
            try container.encode(startParameter, forKey: .startParameter)
            try container.encode(endParameter, forKey: .endParameter)
        case let .constantU(u, vStart, vEnd):
            try container.encode(Kind.constantU, forKey: .kind)
            try container.encode(u, forKey: .u)
            try container.encode(vStart, forKey: .vStart)
            try container.encode(vEnd, forKey: .vEnd)
        case let .constantV(v, uStart, uEnd):
            try container.encode(Kind.constantV, forKey: .kind)
            try container.encode(v, forKey: .v)
            try container.encode(uStart, forKey: .uStart)
            try container.encode(uEnd, forKey: .uEnd)
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            try container.encode(Kind.harmonic, forKey: .kind)
            try container.encode(center, forKey: .center)
            try container.encode(cosine, forKey: .cosine)
            try container.encode(sine, forKey: .sine)
            try container.encode(startParameter, forKey: .startParameter)
            try container.encode(endParameter, forKey: .endParameter)
        case let .polyline(points):
            try container.encode(Kind.polyline, forKey: .kind)
            try container.encode(points, forKey: .points)
        case let .bSpline(curve):
            try container.encode(Kind.bSpline, forKey: .kind)
            try container.encode(curve, forKey: .bSpline)
        case let .certifiedImplicit(curve):
            try container.encode(Kind.certifiedImplicit, forKey: .kind)
            try container.encode(curve, forKey: .certifiedImplicit)
        case let .certifiedAnalyticImplicit(curve):
            try container.encode(Kind.certifiedAnalyticImplicit, forKey: .kind)
            try container.encode(curve, forKey: .certifiedAnalyticImplicit)
        case let .certifiedAnalyticPair(curve):
            try container.encode(Kind.certifiedAnalyticPair, forKey: .kind)
            try container.encode(curve, forKey: .certifiedAnalyticPair)
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            try container.encode(Kind.sphericalGreatCircle, forKey: .kind)
            try container.encode(cosine, forKey: .cosine)
            try container.encode(sine, forKey: .sine)
            try container.encode(startParameter, forKey: .startParameter)
            try container.encode(endParameter, forKey: .endParameter)
        case let .projectedAnalytic(curve):
            try container.encode(Kind.projectedAnalytic, forKey: .kind)
            try container.encode(curve, forKey: .projectedAnalytic)
        case let .rigidImage(curve):
            try container.encode(Kind.rigidImage, forKey: .kind)
            try container.encode(curve, forKey: .rigidImage)
        case let .offsetSurfaceImage(curve):
            try container.encode(Kind.offsetSurfaceImage, forKey: .kind)
            try container.encode(curve, forKey: .offsetSurfaceImage)
        case let .periodicTranslation(base, uShift, vShift):
            try container.encode(Kind.periodicTranslation, forKey: .kind)
            try container.encode(base, forKey: .base)
            try container.encode(uShift, forKey: .uShift)
            try container.encode(vShift, forKey: .vShift)
        }
    }

    private static func closedBounds(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        try domain.validate(tolerance: tolerance)
        guard case let .closed(lower, upper) = domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        return (lower, upper)
    }

    private func validateParameter(
        _ parameter: SurfaceParameter,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try parameter.validate()
        guard try surface.uDomain.contains(parameter.u, tolerance: tolerance),
              try surface.vDomain.contains(parameter.v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
    }

    private func validatePeriodicShift(
        _ shift: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws {
        guard shift.isFinite else {
            throw GeometryError.invalidCoordinate(shift)
        }
        let scale = max(abs(shift), 1.0)
        let resolution = max(
            tolerance.relative * scale,
            Double.ulpOfOne * scale * 128.0
        )
        guard abs(shift) > resolution else { return }
        guard case let .periodic(period) = domain else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: abs(shift),
                tolerance: tolerance,
                message: "A pcurve parameter translation requires a periodic surface domain."
            )
        }
        let periodCount = (shift / period).rounded()
        let residual = abs(shift - periodCount * period)
        guard residual <= resolution else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                residual: residual,
                tolerance: tolerance,
                message: "A pcurve parameter translation must be an integer multiple of the surface period."
            )
        }
    }

    private func polylineParameter(points: [SurfaceParameter], fraction: Double) throws -> SurfaceParameter {
        guard let first = points.first,
              let last = points.last else {
            throw GeometryError.invalidDistance(Double(points.count))
        }
        guard fraction > 0.0 else {
            return first
        }
        guard fraction < 1.0 else {
            return last
        }

        var segmentLengths: [Double] = []
        var totalLength = 0.0
        for index in 1..<points.count {
            let length = parameterDistance(from: points[index - 1], to: points[index])
            segmentLengths.append(length)
            totalLength += length
        }
        guard totalLength > Double.ulpOfOne else {
            throw GeometryError.invalidDistance(totalLength)
        }
        let targetLength = totalLength * fraction
        var accumulatedLength = 0.0
        for index in 0..<segmentLengths.count {
            let nextLength = accumulatedLength + segmentLengths[index]
            if targetLength <= nextLength || index == segmentLengths.count - 1 {
                let segmentFraction = (targetLength - accumulatedLength) / segmentLengths[index]
                return SurfaceParameter(
                    u: interpolated(points[index].u, points[index + 1].u, fraction: segmentFraction),
                    v: interpolated(points[index].v, points[index + 1].v, fraction: segmentFraction)
                )
            }
            accumulatedLength = nextLength
        }
        return last
    }

    private func sphericalParameter(
        cosine: Vector3D,
        sine: Vector3D,
        parameter: Double,
        startParameter: Double,
        endParameter: Double
    ) -> SurfaceParameter {
        let radial = cosine * cos(parameter) + sine * sin(parameter)
        let horizontalLength = hypot(radial.x, radial.y)
        let longitudeDirection: Vector3D
        if horizontalLength <= 1.0e-12,
           let approachDirection = poleApproachDirection(
               parameter: parameter,
               startParameter: startParameter,
               endParameter: endParameter
           ) {
            let derivative = cosine * -sin(parameter) + sine * cos(parameter)
            longitudeDirection = derivative * approachDirection
        } else {
            longitudeDirection = radial
        }
        var longitude = atan2(-longitudeDirection.x, longitudeDirection.y)
        if longitude < 0.0 { longitude += 2.0 * Double.pi }
        return SurfaceParameter(
            u: longitude,
            v: asin(min(max(radial.z, -1.0), 1.0))
        )
    }

    private func poleApproachDirection(
        parameter: Double,
        startParameter: Double,
        endParameter: Double
    ) -> Double? {
        let scale = max(abs(parameter), abs(startParameter), abs(endParameter), 1.0)
        let endpointTolerance = Double.ulpOfOne * scale * 64.0
        let direction = endParameter > startParameter ? 1.0 : -1.0
        if abs(parameter - startParameter) <= endpointTolerance {
            return direction
        }
        if abs(parameter - endParameter) <= endpointTolerance {
            return -direction
        }
        return nil
    }

    private func parameterDistance(from start: SurfaceParameter, to end: SurfaceParameter) -> Double {
        hypot(end.u - start.u, end.v - start.v)
    }

    private func affineParameter(
        origin: Point2D,
        direction: Point2D,
        parameter: Double
    ) -> SurfaceParameter {
        SurfaceParameter(
            u: origin.x + direction.x * parameter,
            v: origin.y + direction.y * parameter
        )
    }

    private func normalizedFraction(
        _ parameter: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try domain.validate(tolerance: tolerance)
        switch domain {
        case let .closed(lower, upper):
            guard parameter >= lower - tolerance.distance,
                  parameter <= upper + tolerance.distance else {
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

    /// Fractions used to trim an authored full-period pcurve. Point
    /// evaluation identifies a period's upper endpoint with zero, while a
    /// monotone trim ending exactly at that upper endpoint must retain the
    /// universal-cover representative at fraction one.
    private func trimFractions(
        from start: Double,
        to end: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> (start: Double, end: Double) {
        let startFraction = try normalizedFraction(
            start,
            domain: domain,
            tolerance: tolerance
        )
        var endFraction = try normalizedFraction(
            end,
            domain: domain,
            tolerance: tolerance
        )
        if case let .periodic(period) = domain {
            let remainder = end.truncatingRemainder(dividingBy: period)
            if end > start,
               abs(remainder) <= tolerance.angle,
               abs(end - period) <= tolerance.angle {
                endFraction = 1.0
            }
        }
        return (startFraction, endFraction)
    }

    private func certifiedLocalFraction(
        _ parameter: Double,
        domain: ParameterDomain,
        startFraction: Double,
        endFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try domain.validate(tolerance: tolerance)
        guard parameter.isFinite,
              startFraction.isFinite,
              endFraction.isFinite,
              abs(endFraction - startFraction) > tolerance.relative else {
            throw GeometryError.invalidDistance(parameter)
        }
        let globalFraction: Double
        switch domain {
        case let .closed(lower, upper):
            guard parameter >= lower - tolerance.distance,
                  parameter <= upper + tolerance.distance else {
                throw GeometryError.invalidDistance(parameter)
            }
            globalFraction = (parameter - lower) / (upper - lower)
        case let .periodic(period):
            globalFraction = parameter / period
        case .unbounded:
            throw GeometryError.invalidDistance(parameter)
        }
        let lower = min(startFraction, endFraction)
        let upper = max(startFraction, endFraction)
        let candidates: [Double]
        if case .periodic = domain {
            let nearestTurn = round((0.5 * (lower + upper)) - globalFraction)
            candidates = [
                globalFraction + nearestTurn,
                globalFraction + nearestTurn - 1.0,
                globalFraction + nearestTurn + 1.0,
            ]
        } else {
            candidates = [globalFraction]
        }
        guard let adjusted = candidates.min(by: { lhs, rhs in
            intervalDistance(lhs, lower: lower, upper: upper)
                < intervalDistance(rhs, lower: lower, upper: upper)
        }), adjusted >= lower - tolerance.relative,
            adjusted <= upper + tolerance.relative else {
            throw GeometryError.invalidDistance(parameter)
        }
        let local = (adjusted - startFraction) / (endFraction - startFraction)
        guard local >= -tolerance.relative,
              local <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(parameter)
        }
        return min(max(local, 0.0), 1.0)
    }

    private func intervalDistance(
        _ value: Double,
        lower: Double,
        upper: Double
    ) -> Double {
        if value < lower { return lower - value }
        if value > upper { return value - upper }
        return 0.0
    }

    private func trimmedPolyline(
        _ points: [SurfaceParameter],
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        switch curveDomain {
        case .unbounded:
            throw GeometryError.invalidDistance(endParameter - startParameter)
        case .closed:
            return try subcurve(
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
        case let .periodic(period):
            let span = endParameter - startParameter
            guard span <= period + tolerance.relative else {
                throw GeometryError.invalidDistance(span)
            }
            let startFraction = try normalizedFraction(
                startParameter,
                domain: curveDomain,
                tolerance: tolerance
            )
            let spanFraction = min(span / period, 1.0)
            let unwrappedEndFraction = startFraction + spanFraction
            if unwrappedEndFraction <= 1.0 + tolerance.relative {
                return try subcurve(
                    fromNormalizedFraction: startFraction,
                    toNormalizedFraction: min(unwrappedEndFraction, 1.0),
                    tolerance: tolerance
                )
            }
            guard let first = points.first,
                  let last = points.last,
                  parameterDistance(from: first, to: last) <= tolerance.distance else {
                throw GeometryError.invalidDistance(span)
            }
            let tail = try subcurve(
                fromNormalizedFraction: startFraction,
                toNormalizedFraction: 1.0,
                tolerance: tolerance
            )
            let head = try subcurve(
                fromNormalizedFraction: 0.0,
                toNormalizedFraction: unwrappedEndFraction - 1.0,
                tolerance: tolerance
            )
            guard case let .polyline(tailPoints) = tail,
                  case let .polyline(headPoints) = head else {
                throw GeometryError.invalidDistance(span)
            }
            return .polyline(tailPoints + headPoints.dropFirst())
        }
    }

    private func harmonicParameter(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        parameter: Double
    ) -> SurfaceParameter {
        SurfaceParameter(
            u: center.x + cosine.x * cos(parameter) + sine.x * sin(parameter),
            v: center.y + cosine.y * cos(parameter) + sine.y * sin(parameter)
        )
    }

    private func harmonicValidationParameters(
        cosine: Point2D,
        sine: Point2D,
        startParameter: Double,
        endParameter: Double
    ) -> [Double] {
        let lower = min(startParameter, endParameter)
        let upper = max(startParameter, endParameter)
        var result = [startParameter, endParameter]
        result.append(contentsOf: harmonicCriticalParameters(
            cosineCoefficient: cosine.x,
            sineCoefficient: sine.x,
            lower: lower,
            upper: upper
        ))
        result.append(contentsOf: harmonicCriticalParameters(
            cosineCoefficient: cosine.y,
            sineCoefficient: sine.y,
            lower: lower,
            upper: upper
        ))
        return result
    }

    private func harmonicCriticalParameters(
        cosineCoefficient: Double,
        sineCoefficient: Double,
        lower: Double,
        upper: Double
    ) -> [Double] {
        guard hypot(cosineCoefficient, sineCoefficient) > Double.leastNonzeroMagnitude else {
            return []
        }
        let firstRoot = atan2(sineCoefficient, cosineCoefficient)
        let period = Double.pi
        let firstIndex = Int(ceil((lower - firstRoot) / period))
        let lastIndex = Int(floor((upper - firstRoot) / period))
        guard firstIndex <= lastIndex else {
            return []
        }
        return (firstIndex...lastIndex).map { index in
            firstRoot + Double(index) * period
        }
    }

    private func interpolated(_ start: Double, _ end: Double, fraction: Double) -> Double {
        start + (end - start) * fraction
    }
}

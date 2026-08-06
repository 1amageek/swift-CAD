import CADCore

public enum SurfaceSurfaceIntersectionCurveTruth: Codable, Hashable, Sendable {
    case parametric(Curve3D)
    case implicit(CertifiedImplicitIntersectionCurve)
    case analyticBSpline(CertifiedAnalyticBSplineIntersectionCurve)
    case analyticBSplineTangency(CertifiedAnalyticBSplineTangencyIntersectionCurve)
    case analyticAnalytic(CertifiedAnalyticAnalyticIntersectionCurve)
    case quadraticTangency(CertifiedQuadraticTangencyIntersectionCurve)

    public var curve: Curve3D {
        switch self {
        case let .parametric(curve):
            curve
        case let .implicit(curve):
            .implicit(curve)
        case let .analyticBSpline(curve):
            curve.curve
        case let .analyticBSplineTangency(curve):
            curve.curve
        case let .analyticAnalytic(curve):
            curve.curve
        case let .quadraticTangency(curve):
            curve.curve
        }
    }

    public func validate(tolerance: ModelingTolerance) throws {
        switch self {
        case let .parametric(curve):
            try curve.validate(tolerance: tolerance)
        case let .implicit(curve):
            try curve.validate(tolerance: tolerance)
        case let .analyticBSpline(curve):
            try curve.validate(tolerance: tolerance)
        case let .analyticBSplineTangency(curve):
            try curve.validate(tolerance: tolerance)
        case let .analyticAnalytic(curve):
            try curve.validate(tolerance: tolerance)
        case let .quadraticTangency(curve):
            try curve.validate(tolerance: tolerance)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case parametric
        case implicit
        case analyticBSpline
        case analyticBSplineTangency
        case analyticAnalytic
        case quadraticTangency
    }

    private enum Kind: String, Codable {
        case parametric
        case implicit
        case analyticBSpline
        case analyticBSplineTangency
        case analyticAnalytic
        case quadraticTangency
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .parametric:
            try container.validateOnlyExpectedKeys([.kind, .parametric], in: decoder)
            self = .parametric(try container.decode(Curve3D.self, forKey: .parametric))
        case .implicit:
            try container.validateOnlyExpectedKeys([.kind, .implicit], in: decoder)
            self = .implicit(try container.decode(
                CertifiedImplicitIntersectionCurve.self,
                forKey: .implicit
            ))
        case .analyticBSpline:
            try container.validateOnlyExpectedKeys([.kind, .analyticBSpline], in: decoder)
            self = .analyticBSpline(try container.decode(
                CertifiedAnalyticBSplineIntersectionCurve.self,
                forKey: .analyticBSpline
            ))
        case .analyticBSplineTangency:
            try container.validateOnlyExpectedKeys(
                [.kind, .analyticBSplineTangency],
                in: decoder
            )
            self = .analyticBSplineTangency(try container.decode(
                CertifiedAnalyticBSplineTangencyIntersectionCurve.self,
                forKey: .analyticBSplineTangency
            ))
        case .analyticAnalytic:
            try container.validateOnlyExpectedKeys([.kind, .analyticAnalytic], in: decoder)
            self = .analyticAnalytic(try container.decode(
                CertifiedAnalyticAnalyticIntersectionCurve.self,
                forKey: .analyticAnalytic
            ))
        case .quadraticTangency:
            try container.validateOnlyExpectedKeys([.kind, .quadraticTangency], in: decoder)
            self = .quadraticTangency(try container.decode(
                CertifiedQuadraticTangencyIntersectionCurve.self,
                forKey: .quadraticTangency
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .parametric(curve):
            try container.encode(Kind.parametric, forKey: .kind)
            try container.encode(curve, forKey: .parametric)
        case let .implicit(curve):
            try container.encode(Kind.implicit, forKey: .kind)
            try container.encode(curve, forKey: .implicit)
        case let .analyticBSpline(curve):
            try container.encode(Kind.analyticBSpline, forKey: .kind)
            try container.encode(curve, forKey: .analyticBSpline)
        case let .analyticBSplineTangency(curve):
            try container.encode(Kind.analyticBSplineTangency, forKey: .kind)
            try container.encode(curve, forKey: .analyticBSplineTangency)
        case let .analyticAnalytic(curve):
            try container.encode(Kind.analyticAnalytic, forKey: .kind)
            try container.encode(curve, forKey: .analyticAnalytic)
        case let .quadraticTangency(curve):
            try container.encode(Kind.quadraticTangency, forKey: .kind)
            try container.encode(curve, forKey: .quadraticTangency)
        }
    }
}


// The synthesized equality binds every large certified payload pair in one
// frame, which overflows 512 KB worker stacks in unoptimized builds, so the
// dispatch below binds payloads only inside per-case helpers.
extension SurfaceSurfaceIntersectionCurveTruth {
    public static func == (
        lhs: SurfaceSurfaceIntersectionCurveTruth,
        rhs: SurfaceSurfaceIntersectionCurveTruth
    ) -> Bool {
        switch (lhs, rhs) {
        case (.parametric, .parametric):
            return equalsParametric(lhs, rhs)
        case (.implicit, .implicit):
            return equalsImplicit(lhs, rhs)
        case (.analyticBSpline, .analyticBSpline):
            return equalsAnalyticBSpline(lhs, rhs)
        case (.analyticBSplineTangency, .analyticBSplineTangency):
            return equalsAnalyticBSplineTangency(lhs, rhs)
        case (.analyticAnalytic, .analyticAnalytic):
            return equalsAnalyticAnalytic(lhs, rhs)
        case (.quadraticTangency, .quadraticTangency):
            return equalsQuadraticTangency(lhs, rhs)
        default:
            return false
        }
    }

    @inline(never)
    private static func equalsParametric(_ lhs: Self, _ rhs: Self) -> Bool {
        guard case let .parametric(l) = lhs, case let .parametric(r) = rhs else { return false }
        return l == r
    }

    @inline(never)
    private static func equalsImplicit(_ lhs: Self, _ rhs: Self) -> Bool {
        guard case let .implicit(l) = lhs, case let .implicit(r) = rhs else { return false }
        return l == r
    }

    @inline(never)
    private static func equalsAnalyticBSpline(_ lhs: Self, _ rhs: Self) -> Bool {
        guard case let .analyticBSpline(l) = lhs, case let .analyticBSpline(r) = rhs else { return false }
        return l == r
    }

    @inline(never)
    private static func equalsAnalyticBSplineTangency(_ lhs: Self, _ rhs: Self) -> Bool {
        guard case let .analyticBSplineTangency(l) = lhs, case let .analyticBSplineTangency(r) = rhs else { return false }
        return l == r
    }

    @inline(never)
    private static func equalsAnalyticAnalytic(_ lhs: Self, _ rhs: Self) -> Bool {
        guard case let .analyticAnalytic(l) = lhs, case let .analyticAnalytic(r) = rhs else { return false }
        return l == r
    }

    @inline(never)
    private static func equalsQuadraticTangency(_ lhs: Self, _ rhs: Self) -> Bool {
        guard case let .quadraticTangency(l) = lhs, case let .quadraticTangency(r) = rhs else { return false }
        return l == r
    }
}

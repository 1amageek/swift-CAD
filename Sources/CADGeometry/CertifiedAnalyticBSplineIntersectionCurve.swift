import CADCore

public struct CertifiedAnalyticBSplineIntersectionCurve: Codable, Hashable, Sendable {
    public let implicitCurve: CertifiedImplicitIntersectionCurve
    public let analyticSurface: Surface3D
    public let analyticIsFirst: Bool
    public let periodicSeamOffset: Double

    public var curve: Curve3D { .implicit(implicitCurve) }

    public var boundedSurface: BSplineSurface3D {
        analyticIsFirst ? implicitCurve.secondSurface : implicitCurve.firstSurface
    }

    public var firstSurfaceParameterCurve: SurfaceParameterCurve {
        if analyticIsFirst {
            return .certifiedAnalyticImplicit(CertifiedAnalyticImplicitSurfaceParameterCurve(
                validatedIntersection: self,
                startFraction: 0.0,
                endFraction: 1.0
            ))
        }
        return .certifiedImplicit(CertifiedImplicitSurfaceParameterCurve(
            validatedIntersection: implicitCurve,
            role: .first
        ))
    }

    public var secondSurfaceParameterCurve: SurfaceParameterCurve {
        if analyticIsFirst {
            return .certifiedImplicit(CertifiedImplicitSurfaceParameterCurve(
                validatedIntersection: implicitCurve,
                role: .second
            ))
        }
        return .certifiedAnalyticImplicit(CertifiedAnalyticImplicitSurfaceParameterCurve(
            validatedIntersection: self,
            startFraction: 0.0,
            endFraction: 1.0
        ))
    }

    public init(
        implicitCurve: CertifiedImplicitIntersectionCurve,
        analyticSurface: Surface3D,
        analyticIsFirst: Bool,
        periodicSeamOffset: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.implicitCurve = implicitCurve
        self.analyticSurface = analyticSurface
        self.analyticIsFirst = analyticIsFirst
        self.periodicSeamOffset = periodicSeamOffset
        try validate(tolerance: tolerance)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try implicitCurve.validate(tolerance: tolerance)
        try analyticSurface.validate(tolerance: tolerance)
        guard periodicSeamOffset.isFinite else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic implicit intersection requires a finite seam offset."
            )
        }
        let canonical = CanonicalAnalyticSurface(analyticSurface)
        switch canonical {
        case .plane, .cylinder, .cone, .sphere, .torus:
            break
        case .unsupported:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic implicit intersection requires an exact analytic surface."
            )
        }
        let rebuilt = try AnalyticSurfaceBSplineBuilder().surface(
            for: canonical,
            boundedBy: boundedSurface,
            periodicSeamOffset: periodicSeamOffset,
            tolerance: implicitCurve.certificationTolerance
        )
        let storedAnalytic = analyticIsFirst
            ? implicitCurve.firstSurface
            : implicitCurve.secondSurface
        guard rebuilt == storedAnalytic else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "The stored implicit surface does not reproduce the exact analytic NURBS conversion."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case implicitCurve
        case analyticSurface
        case analyticIsFirst
        case periodicSeamOffset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.implicitCurve, .analyticSurface, .analyticIsFirst, .periodicSeamOffset],
            in: decoder
        )
        let implicitCurve = try container.decode(
            CertifiedImplicitIntersectionCurve.self,
            forKey: .implicitCurve
        )
        try self.init(
            implicitCurve: implicitCurve,
            analyticSurface: container.decode(Surface3D.self, forKey: .analyticSurface),
            analyticIsFirst: container.decode(Bool.self, forKey: .analyticIsFirst),
            periodicSeamOffset: container.decode(Double.self, forKey: .periodicSeamOffset),
            tolerance: implicitCurve.certificationTolerance
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: implicitCurve.certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(implicitCurve, forKey: .implicitCurve)
        try container.encode(analyticSurface, forKey: .analyticSurface)
        try container.encode(analyticIsFirst, forKey: .analyticIsFirst)
        try container.encode(periodicSeamOffset, forKey: .periodicSeamOffset)
    }
}

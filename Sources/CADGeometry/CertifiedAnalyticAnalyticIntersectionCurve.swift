import CADCore

public struct CertifiedAnalyticAnalyticIntersectionCurve: Codable, Hashable, Sendable {
    public let planeTorusCurve: CertifiedPlaneTorusIntersectionCurve
    public let firstSurface: Surface3D
    public let secondSurface: Surface3D
    public let planeIsFirst: Bool

    public var curve: Curve3D {
        .analytic(.planeTorus(planeTorusCurve))
    }

    public var certificationTolerance: ModelingTolerance {
        planeTorusCurve.certificationTolerance
    }

    public var maximumResidualUpperBound: Double {
        planeTorusCurve.maximumResidualUpperBound
    }

    public var firstSurfaceParameterCurve: SurfaceParameterCurve {
        .certifiedAnalyticPair(CertifiedAnalyticPairSurfaceParameterCurve(
            validatedIntersection: self,
            role: .first,
            startFraction: 0.0,
            endFraction: 1.0
        ))
    }

    public var secondSurfaceParameterCurve: SurfaceParameterCurve {
        .certifiedAnalyticPair(CertifiedAnalyticPairSurfaceParameterCurve(
            validatedIntersection: self,
            role: .second,
            startFraction: 0.0,
            endFraction: 1.0
        ))
    }

    public init(
        planeTorusCurve: CertifiedPlaneTorusIntersectionCurve,
        firstSurface: Surface3D,
        secondSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        self.planeTorusCurve = planeTorusCurve
        self.firstSurface = firstSurface
        self.secondSurface = secondSurface
        if firstSurface == planeTorusCurve.planeSurface,
           secondSurface == planeTorusCurve.torusSurface {
            planeIsFirst = true
        } else if firstSurface == planeTorusCurve.torusSurface,
                  secondSurface == planeTorusCurve.planeSurface {
            planeIsFirst = false
        } else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "An analytic-pair curve must preserve its exact source surfaces."
            )
        }
        try validate(tolerance: tolerance)
    }

    public func surface(for role: SurfaceIntersectionSurfaceRole) -> Surface3D {
        role == .first ? firstSurface : secondSurface
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try planeTorusCurve.point(
            at: try curveParameter(fraction, tolerance: tolerance),
            tolerance: tolerance
        )
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> CertifiedPlaneTorusIntersectionCurve.DifferentialGeometry {
        let geometry = try planeTorusCurve.differentialGeometry(
            at: try curveParameter(fraction, tolerance: tolerance),
            tolerance: tolerance
        )
        let scale = 2.0 * Double.pi
        return CertifiedPlaneTorusIntersectionCurve.DifferentialGeometry(
            position: geometry.position,
            firstDerivative: geometry.firstDerivative * scale,
            secondDerivative: geometry.secondDerivative * (scale * scale)
        )
    }

    public func internalParameter(
        for role: SurfaceIntersectionSurfaceRole,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        let parameters = try planeTorusCurve.surfaceParameters(
            at: try curveParameter(fraction, tolerance: tolerance),
            tolerance: tolerance
        )
        if planeIsFirst {
            return role == .first ? parameters.plane : parameters.torus
        }
        return role == .first ? parameters.torus : parameters.plane
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try planeTorusCurve.validate(tolerance: tolerance)
        try firstSurface.validate(tolerance: tolerance)
        try secondSurface.validate(tolerance: tolerance)
        guard (planeIsFirst
            && firstSurface == planeTorusCurve.planeSurface
            && secondSurface == planeTorusCurve.torusSurface)
            || (planeIsFirst == false
                && firstSurface == planeTorusCurve.torusSurface
                && secondSurface == planeTorusCurve.planeSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A stored analytic-pair curve changed source-surface order."
            )
        }
    }

    private func curveParameter(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        return min(max(fraction, 0.0), 1.0) * 2.0 * Double.pi
    }

    private enum CodingKeys: String, CodingKey {
        case planeTorusCurve
        case firstSurface
        case secondSurface
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [.planeTorusCurve, .firstSurface, .secondSurface],
            in: decoder
        )
        let planeTorusCurve = try container.decode(
            CertifiedPlaneTorusIntersectionCurve.self,
            forKey: .planeTorusCurve
        )
        try self.init(
            planeTorusCurve: planeTorusCurve,
            firstSurface: container.decode(Surface3D.self, forKey: .firstSurface),
            secondSurface: container.decode(Surface3D.self, forKey: .secondSurface),
            tolerance: planeTorusCurve.certificationTolerance
        )
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(planeTorusCurve, forKey: .planeTorusCurve)
        try container.encode(firstSurface, forKey: .firstSurface)
        try container.encode(secondSurface, forKey: .secondSurface)
    }
}

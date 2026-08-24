import CADCore
import Foundation

public struct CertifiedBoundedPlaneConeIntersectionCurve: Codable, Hashable, Sendable {
    public struct DifferentialGeometry: Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
    }

    public let planeSurface: Surface3D
    public let coneSurface: Surface3D
    public let analyticCurve: AnalyticCurve3D
    public let startParameter: Double
    public let endParameter: Double
    public let certificationTolerance: ModelingTolerance
    public let maximumResidualUpperBound: Double

    public init(
        planeSurface: Surface3D,
        coneSurface: Surface3D,
        analyticCurve: AnalyticCurve3D,
        startParameter: Double,
        endParameter: Double,
        tolerance: ModelingTolerance
    ) throws {
        self.planeSurface = planeSurface
        self.coneSurface = coneSurface
        self.analyticCurve = analyticCurve
        self.startParameter = startParameter
        self.endParameter = endParameter
        certificationTolerance = tolerance
        maximumResidualUpperBound = tolerance.distance
        try validate(tolerance: tolerance)
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        try certificationTolerance.validate()
        guard certificationTolerance.distance <= tolerance.distance,
              certificationTolerance.angle <= tolerance.angle,
              certificationTolerance.relative <= tolerance.relative else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded plane-cone curve cannot satisfy a stricter tolerance than its stored certificate."
            )
        }
        guard case .plane = CanonicalAnalyticSurface(planeSurface),
              case .cone = CanonicalAnalyticSurface(coneSurface) else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded plane-cone curve requires one plane and one cone."
            )
        }
        switch analyticCurve {
        case .hyperbola, .parabola:
            break
        case .line, .circle, .arc, .ellipse, .planeTorus:
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded plane-cone curve requires an exact hyperbola or parabola."
            )
        }
        try planeSurface.validate(tolerance: tolerance)
        try coneSurface.validate(tolerance: tolerance)
        try analyticCurve.validate(tolerance: tolerance)
        guard startParameter.isFinite,
              endParameter.isFinite,
              endParameter > startParameter,
              maximumResidualUpperBound == certificationTolerance.distance,
              maximumResidualUpperBound <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: maximumResidualUpperBound,
                tolerance: tolerance,
                message: "A bounded plane-cone curve has an invalid interval or residual certificate."
            )
        }
        let exactCandidates = try Self.exactAnalyticCandidates(
            planeSurface: planeSurface,
            coneSurface: coneSurface,
            tolerance: tolerance
        )
        guard exactCandidates.contains(analyticCurve) else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                tolerance: tolerance,
                message: "A bounded plane-cone curve no longer matches the exact conic classified from its source surfaces."
            )
        }
        let start = try analyticCurve.point(at: startParameter, tolerance: tolerance)
        let end = try analyticCurve.point(at: endParameter, tolerance: tolerance)
        guard (end - start).length > tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .singularGeometry,
                residual: (end - start).length,
                tolerance: tolerance,
                message: "A bounded plane-cone interval collapsed within modeling tolerance."
            )
        }
        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let point = try self.point(
                atNormalizedFraction: fraction,
                tolerance: tolerance,
                validatingCertificate: false
            )
            try verify(point: point, on: planeSurface, tolerance: tolerance)
            try verify(point: point, on: coneSurface, tolerance: tolerance)
        }
    }

    public func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try validate(tolerance: tolerance)
        return try point(
            atNormalizedFraction: fraction,
            tolerance: tolerance,
            validatingCertificate: false
        )
    }

    public func differential(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        try validate(tolerance: tolerance)
        let parameter = try mappedParameter(fraction, tolerance: tolerance)
        let geometry = try analyticCurve.differentialGeometry(
            at: parameter,
            tolerance: tolerance
        )
        let scale = endParameter - startParameter
        return DifferentialGeometry(
            position: geometry.position,
            firstDerivative: geometry.firstDerivative * scale,
            secondDerivative: geometry.secondDerivative * (scale * scale)
        )
    }

    func thirdDerivative(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        let parameter = try mappedParameter(fraction, tolerance: tolerance)
        let derivative = try Curve3D.analytic(analyticCurve)
            .parameterDerivativesThroughThirdOrder(
                at: parameter,
                tolerance: tolerance
            ).thirdDerivative
        let scale = endParameter - startParameter
        return derivative * (scale * scale * scale)
    }

    public func parameter(
        on surface: Surface3D,
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        try validate(tolerance: tolerance)
        guard surface == planeSurface || surface == coneSurface else {
            throw KernelError(
                phase: .geometry,
                code: .invalidInput,
                tolerance: tolerance,
                message: "A bounded plane-cone pcurve was requested on an unrelated surface."
            )
        }
        let point = try self.point(
            atNormalizedFraction: fraction,
            tolerance: tolerance,
            validatingCertificate: false
        )
        let projection = try surface.parameterProjection(of: point, tolerance: tolerance)
        let u: Double
        if surface == coneSurface {
            let middlePoint = try self.point(
                atNormalizedFraction: 0.5,
                tolerance: tolerance,
                validatingCertificate: false
            )
            let middleProjection = try coneSurface.parameterProjection(
                of: middlePoint,
                tolerance: tolerance
            )
            u = Self.unwrappedAngle(projection.u, nearest: middleProjection.u)
        } else {
            u = projection.u
        }
        let reconstructed = try surface.point(
            u: u,
            v: projection.v,
            tolerance: tolerance
        )
        let residual = (reconstructed - point).length
        guard residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "A bounded plane-cone pcurve failed exact point reconstruction."
            )
        }
        return SurfaceParameter(u: u, v: projection.v)
    }

    public func boundingBox(tolerance: ModelingTolerance) throws -> BoundingBox3D {
        try validate(tolerance: tolerance)
        var parameters = [startParameter, endParameter]
        switch analyticCurve {
        case let .hyperbola(curve):
            let conjugateAxis = try curve.normal.cross(curve.transverseAxis).normalized(
                tolerance: tolerance.distance
            )
            let first = curve.transverseAxis * curve.transverseRadius
            let second = conjugateAxis * curve.conjugateRadius
            for (a, b) in [
                (first.x, second.x),
                (first.y, second.y),
                (first.z, second.z),
            ] where abs(a) > Double.leastNonzeroMagnitude {
                let ratio = -b / a
                if abs(ratio) < 1.0 {
                    let candidate = atanh(ratio)
                    if candidate > startParameter, candidate < endParameter {
                        parameters.append(candidate)
                    }
                }
            }
        case let .parabola(curve):
            let transverseAxis = try curve.normal.cross(curve.axis).normalized(
                tolerance: tolerance.distance
            )
            let quadratic = curve.axis * (1.0 / (4.0 * curve.focalLength))
            for (linear, second) in [
                (transverseAxis.x, quadratic.x),
                (transverseAxis.y, quadratic.y),
                (transverseAxis.z, quadratic.z),
            ] where abs(second) > Double.leastNonzeroMagnitude {
                let candidate = -linear / (2.0 * second)
                if candidate > startParameter, candidate < endParameter {
                    parameters.append(candidate)
                }
            }
        case .line, .circle, .arc, .ellipse, .planeTorus:
            break
        }
        return try BoundingBox3D(points: parameters.map {
            try analyticCurve.point(at: $0, tolerance: tolerance)
        })
    }

    private func point(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance,
        validatingCertificate: Bool
    ) throws -> Point3D {
        if validatingCertificate {
            try validate(tolerance: tolerance)
        }
        return try analyticCurve.point(
            at: mappedParameter(fraction, tolerance: tolerance),
            tolerance: tolerance
        )
    }

    private func mappedParameter(
        _ fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> Double {
        guard fraction.isFinite,
              fraction >= -tolerance.relative,
              fraction <= 1.0 + tolerance.relative else {
            throw GeometryError.invalidDistance(fraction)
        }
        return startParameter
            + (endParameter - startParameter) * min(max(fraction, 0.0), 1.0)
    }

    private func verify(
        point: Point3D,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        let projection = try surface.parameterProjection(of: point, tolerance: tolerance)
        guard projection.residual <= tolerance.distance else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: projection.residual,
                tolerance: tolerance,
                message: "A bounded plane-cone certificate exceeded its source-surface residual."
            )
        }
    }

    private static func exactAnalyticCandidates(
        planeSurface: Surface3D,
        coneSurface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> [AnalyticCurve3D] {
        guard case let .plane(plane) = CanonicalAnalyticSurface(planeSurface),
              case let .cone(cone) = CanonicalAnalyticSurface(coneSurface) else {
            return []
        }
        return try PlaneConeSurfaceIntersector().intersections(
            plane: plane,
            cone: cone,
            firstSurface: planeSurface,
            secondSurface: coneSurface,
            tolerance: tolerance
        ).compactMap { intersection in
            guard case let .curve(value) = intersection,
                  case let .parametric(.analytic(curve)) = value.truth else {
                return nil
            }
            switch curve {
            case .hyperbola, .parabola:
                return curve
            case .line, .circle, .arc, .ellipse, .planeTorus:
                return nil
            }
        }
    }

    private static func unwrappedAngle(_ angle: Double, nearest reference: Double) -> Double {
        let period = 2.0 * Double.pi
        return angle + ((reference - angle) / period).rounded() * period
    }

    private enum CodingKeys: String, CodingKey {
        case planeSurface
        case coneSurface
        case analyticCurve
        case startParameter
        case endParameter
        case certificationTolerance
        case maximumResidualUpperBound
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try container.validateOnlyExpectedKeys(
            [
                .planeSurface,
                .coneSurface,
                .analyticCurve,
                .startParameter,
                .endParameter,
                .certificationTolerance,
                .maximumResidualUpperBound,
            ],
            in: decoder
        )
        let tolerance = try container.decode(
            ModelingTolerance.self,
            forKey: .certificationTolerance
        )
        try self.init(
            planeSurface: container.decode(Surface3D.self, forKey: .planeSurface),
            coneSurface: container.decode(Surface3D.self, forKey: .coneSurface),
            analyticCurve: container.decode(AnalyticCurve3D.self, forKey: .analyticCurve),
            startParameter: container.decode(Double.self, forKey: .startParameter),
            endParameter: container.decode(Double.self, forKey: .endParameter),
            tolerance: tolerance
        )
        let storedBound = try container.decode(
            Double.self,
            forKey: .maximumResidualUpperBound
        )
        guard storedBound == maximumResidualUpperBound else {
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: storedBound,
                tolerance: tolerance,
                message: "A decoded bounded plane-cone residual certificate was altered."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        try validate(tolerance: certificationTolerance)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(planeSurface, forKey: .planeSurface)
        try container.encode(coneSurface, forKey: .coneSurface)
        try container.encode(analyticCurve, forKey: .analyticCurve)
        try container.encode(startParameter, forKey: .startParameter)
        try container.encode(endParameter, forKey: .endParameter)
        try container.encode(certificationTolerance, forKey: .certificationTolerance)
        try container.encode(maximumResidualUpperBound, forKey: .maximumResidualUpperBound)
    }
}

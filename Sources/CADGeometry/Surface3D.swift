import Foundation
import CADCore

public enum Surface3D: Codable, Sendable, Hashable {
    public struct DifferentialGeometry: Codable, Sendable, Hashable {
        public var position: Point3D
        public var tangentU: Vector3D
        public var tangentV: Vector3D
        public var secondDerivativeUU: Vector3D
        public var secondDerivativeUV: Vector3D
        public var secondDerivativeVV: Vector3D
        public var normal: Vector3D
        public var normalCurvatureU: Double
        public var normalCurvatureV: Double
        public var meanCurvature: Double
        public var gaussianCurvature: Double
        public var minimumPrincipalCurvature: Double
        public var maximumPrincipalCurvature: Double
        public var minimumPrincipalDirection: Vector3D
        public var maximumPrincipalDirection: Vector3D

        public init(
            position: Point3D,
            tangentU: Vector3D,
            tangentV: Vector3D,
            secondDerivativeUU: Vector3D,
            secondDerivativeUV: Vector3D,
            secondDerivativeVV: Vector3D,
            normal: Vector3D,
            normalCurvatureU: Double,
            normalCurvatureV: Double,
            meanCurvature: Double,
            gaussianCurvature: Double,
            minimumPrincipalCurvature: Double,
            maximumPrincipalCurvature: Double,
            minimumPrincipalDirection: Vector3D,
            maximumPrincipalDirection: Vector3D
        ) {
            self.position = position
            self.tangentU = tangentU
            self.tangentV = tangentV
            self.secondDerivativeUU = secondDerivativeUU
            self.secondDerivativeUV = secondDerivativeUV
            self.secondDerivativeVV = secondDerivativeVV
            self.normal = normal
            self.normalCurvatureU = normalCurvatureU
            self.normalCurvatureV = normalCurvatureV
            self.meanCurvature = meanCurvature
            self.gaussianCurvature = gaussianCurvature
            self.minimumPrincipalCurvature = minimumPrincipalCurvature
            self.maximumPrincipalCurvature = maximumPrincipalCurvature
            self.minimumPrincipalDirection = minimumPrincipalDirection
            self.maximumPrincipalDirection = maximumPrincipalDirection
        }
    }

    case plane(Plane3D)
    case cylinder(Cylinder3D)
    case analytic(AnalyticSurface3D)
    case bSpline(BSplineSurface3D)
    indirect case procedural(ProceduralSurface3D)

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        switch self {
        case let .plane(plane):
            try plane.validate(tolerance: tolerance)
        case let .cylinder(cylinder):
            try cylinder.validate(tolerance: tolerance)
        case let .analytic(surface):
            try surface.validate(tolerance: tolerance)
        case let .bSpline(surface):
            try surface.validate(tolerance: tolerance)
        case let .procedural(surface):
            try surface.validate(tolerance: tolerance)
        }
    }

    public func point(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try validate(tolerance: tolerance)
        return try pointAssumingValid(u: u, v: v, tolerance: tolerance)
    }

    package func pointAssumingValid(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        switch self {
        case let .plane(plane):
            let (basisU, basisV) = try planeBasis(for: plane, tolerance: tolerance)
            return plane.origin + basisU * u + basisV * v
        case let .cylinder(cylinder):
            let (radialU, radialV) = try cylinderBasis(for: cylinder, tolerance: tolerance)
            let radial = radialU * cos(u) + radialV * sin(u)
            return cylinder.origin + radial * cylinder.radius + cylinder.axis * v
        case let .analytic(surface):
            return try surface.point(u: u, v: v, tolerance: tolerance)
        case let .bSpline(surface):
            return try surface.pointAssumingValid(
                u: u,
                v: v,
                tolerance: tolerance
            )
        case let .procedural(surface):
            return try surface.point(u: u, v: v, tolerance: tolerance)
        }
    }

    public func parameterProjection(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjection {
        switch try parameterProjectionResult(
            of: point,
            options: options,
            tolerance: tolerance
        ) {
        case let .projected(projection):
            return projection
        case let .outsideTolerance(residual):
            throw KernelError(
                phase: .geometry,
                code: .intersectionFailure,
                residual: residual,
                tolerance: tolerance,
                message: "Point does not lie on the requested surface within tolerance."
            )
        }
    }

    /// Separates a verified geometric miss from failures that prevent the
    /// projection algorithm from deciding membership.
    public func parameterProjectionResult(
        of point: Point3D,
        options: SurfaceParameterProjectionOptions = .init(),
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterProjectionResult {
        try options.validate(tolerance: tolerance)
        try validate(tolerance: tolerance)
        try point.validate()
        let parameters: (u: Double, v: Double)
        switch self {
        case let .plane(plane):
            let (basisU, basisV) = try planeBasis(for: plane, tolerance: tolerance)
            let offset = point - plane.origin
            parameters = (offset.dot(basisU), offset.dot(basisV))
        case let .cylinder(cylinder):
            let (radialU, radialV) = try cylinderBasis(for: cylinder, tolerance: tolerance)
            let offset = point - cylinder.origin
            let height = offset.dot(cylinder.axis)
            let radial = offset - cylinder.axis * height
            parameters = (Self.normalizedAngle(atan2(radial.dot(radialV), radial.dot(radialU))), height)
        case let .analytic(surface):
            parameters = try Self.analyticParameters(for: point, on: surface, tolerance: tolerance)
        case let .bSpline(surface):
            return try surface.parameterProjectionResult(
                of: point,
                options: options,
                tolerance: tolerance
            )
        case let .procedural(surface):
            return try surface.parameterProjectionResult(
                of: point,
                options: options,
                tolerance: tolerance
            )
        }
        let projectedPoint = try self.point(u: parameters.u, v: parameters.v, tolerance: tolerance)
        let residual = (point - projectedPoint).length
        guard residual <= tolerance.distance else {
            return .outsideTolerance(residual: residual)
        }
        return .projected(try SurfaceParameterProjection(
            u: parameters.u,
            v: parameters.v,
            point: projectedPoint,
            residual: residual
        ))
    }

    public func normal(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> Vector3D {
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        let point = try point(u: u, v: v, tolerance: tolerance)
        return try DefaultSurfaceNormalResolver().normal(
            at: point,
            on: self,
            u: u,
            v: v,
            tolerance: tolerance
        )
    }

    public func differentialGeometry(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        switch self {
        case let .plane(plane):
            let (basisU, basisV) = try planeBasis(for: plane, tolerance: tolerance)
            return DifferentialGeometry(
                position: plane.origin + basisU * u + basisV * v,
                tangentU: basisU,
                tangentV: basisV,
                secondDerivativeUU: .zero,
                secondDerivativeUV: .zero,
                secondDerivativeVV: .zero,
                normal: plane.normal,
                normalCurvatureU: 0.0,
                normalCurvatureV: 0.0,
                meanCurvature: 0.0,
                gaussianCurvature: 0.0,
                minimumPrincipalCurvature: 0.0,
                maximumPrincipalCurvature: 0.0,
                minimumPrincipalDirection: basisU,
                maximumPrincipalDirection: basisV
            )
        case let .cylinder(cylinder):
            let (radialU, radialV) = try cylinderBasis(for: cylinder, tolerance: tolerance)
            let radial = radialU * cos(u) + radialV * sin(u)
            let tangentU = radialU * (-cylinder.radius * sin(u)) +
                radialV * (cylinder.radius * cos(u))
            let tangentV = cylinder.axis
            let secondDerivativeUU = radial * -cylinder.radius
            let normal = try radial.normalized(tolerance: tolerance.distance)
            let minimumCurvature = -1.0 / cylinder.radius
            return DifferentialGeometry(
                position: cylinder.origin + radial * cylinder.radius + cylinder.axis * v,
                tangentU: tangentU,
                tangentV: tangentV,
                secondDerivativeUU: secondDerivativeUU,
                secondDerivativeUV: .zero,
                secondDerivativeVV: .zero,
                normal: normal,
                normalCurvatureU: minimumCurvature,
                normalCurvatureV: 0.0,
                meanCurvature: minimumCurvature / 2.0,
                gaussianCurvature: 0.0,
                minimumPrincipalCurvature: minimumCurvature,
                maximumPrincipalCurvature: 0.0,
                minimumPrincipalDirection: try tangentU.normalized(tolerance: tolerance.distance),
                maximumPrincipalDirection: tangentV
            )
        case let .analytic(surface):
            let geometry = try surface.differentialGeometry(u: u, v: v, tolerance: tolerance)
            return DifferentialGeometry(
                position: geometry.position,
                tangentU: geometry.tangentU,
                tangentV: geometry.tangentV,
                secondDerivativeUU: geometry.secondDerivativeUU,
                secondDerivativeUV: geometry.secondDerivativeUV,
                secondDerivativeVV: geometry.secondDerivativeVV,
                normal: geometry.normal,
                normalCurvatureU: geometry.normalCurvatureU,
                normalCurvatureV: geometry.normalCurvatureV,
                meanCurvature: geometry.meanCurvature,
                gaussianCurvature: geometry.gaussianCurvature,
                minimumPrincipalCurvature: geometry.minimumPrincipalCurvature,
                maximumPrincipalCurvature: geometry.maximumPrincipalCurvature,
                minimumPrincipalDirection: geometry.minimumPrincipalDirection,
                maximumPrincipalDirection: geometry.maximumPrincipalDirection
            )
        case let .bSpline(surface):
            let geometry = try surface.differentialGeometry(atU: u, v: v, tolerance: tolerance)
            return DifferentialGeometry(
                position: geometry.position,
                tangentU: geometry.tangentU,
                tangentV: geometry.tangentV,
                secondDerivativeUU: geometry.secondDerivativeUU,
                secondDerivativeUV: geometry.secondDerivativeUV,
                secondDerivativeVV: geometry.secondDerivativeVV,
                normal: geometry.normal,
                normalCurvatureU: geometry.normalCurvatureU,
                normalCurvatureV: geometry.normalCurvatureV,
                meanCurvature: geometry.meanCurvature,
                gaussianCurvature: geometry.gaussianCurvature,
                minimumPrincipalCurvature: geometry.minimumPrincipalCurvature,
                maximumPrincipalCurvature: geometry.maximumPrincipalCurvature,
                minimumPrincipalDirection: geometry.minimumPrincipalDirection,
                maximumPrincipalDirection: geometry.maximumPrincipalDirection
            )
        case let .procedural(surface):
            let derivatives = try surface.parameterDerivatives(
                atU: u,
                v: v,
                tolerance: tolerance
            )
            return try SurfaceDifferentialGeometryBuilder().differentialGeometry(
                derivatives: derivatives,
                tolerance: tolerance
            )
        }
    }

    public func uvnFrame(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance
    ) throws -> UVNFrame {
        let differential = try differentialGeometry(atU: u, v: v, tolerance: tolerance)
        let tangentU = try differential.tangentU.normalized(tolerance: tolerance.distance)
        let normal = try differential.normal.normalized(tolerance: tolerance.distance)
        let tangentV = try normal.cross(tangentU).normalized(tolerance: tolerance.distance)
        return try UVNFrame(
            position: differential.position,
            u: tangentU,
            v: tangentV,
            normal: normal,
            tolerance: tolerance
        )
    }

    public var uDomain: ParameterDomain {
        switch self {
        case .plane:
            .unbounded
        case .cylinder:
            .periodic(period: Double.pi * 2.0)
        case let .analytic(surface):
            Self.parameterDomain(surface.uDomain)
        case .bSpline(let surface):
            surface.uDomain
        case let .procedural(surface):
            surface.uDomain
        }
    }

    public var vDomain: ParameterDomain {
        switch self {
        case .plane, .cylinder:
            .unbounded
        case let .analytic(surface):
            Self.parameterDomain(surface.vDomain)
        case .bSpline(let surface):
            surface.vDomain
        case let .procedural(surface):
            surface.vDomain
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case plane
        case cylinder
        case analytic
        case bSpline
        case procedural
    }

    private enum Kind: String, Codable {
        case plane
        case cylinder
        case analytic
        case bSpline
        case procedural
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .plane:
            try container.validateOnlyExpectedKeys([.kind, .plane], in: decoder)
            self = .plane(try container.decode(Plane3D.self, forKey: .plane))
        case .cylinder:
            try container.validateOnlyExpectedKeys([.kind, .cylinder], in: decoder)
            self = .cylinder(try container.decode(Cylinder3D.self, forKey: .cylinder))
        case .analytic:
            try container.validateOnlyExpectedKeys([.kind, .analytic], in: decoder)
            self = .analytic(try container.decode(AnalyticSurface3D.self, forKey: .analytic))
        case .bSpline:
            try container.validateOnlyExpectedKeys([.kind, .bSpline], in: decoder)
            self = .bSpline(try container.decode(BSplineSurface3D.self, forKey: .bSpline))
        case .procedural:
            try container.validateOnlyExpectedKeys([.kind, .procedural], in: decoder)
            self = .procedural(
                try container.decode(ProceduralSurface3D.self, forKey: .procedural)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .plane(plane):
            try container.encode(Kind.plane, forKey: .kind)
            try container.encode(plane, forKey: .plane)
        case let .cylinder(cylinder):
            try container.encode(Kind.cylinder, forKey: .kind)
            try container.encode(cylinder, forKey: .cylinder)
        case let .analytic(surface):
            try container.encode(Kind.analytic, forKey: .kind)
            try container.encode(surface, forKey: .analytic)
        case let .bSpline(surface):
            try container.encode(Kind.bSpline, forKey: .kind)
            try container.encode(surface, forKey: .bSpline)
        case let .procedural(surface):
            try container.encode(Kind.procedural, forKey: .kind)
            try container.encode(surface, forKey: .procedural)
        }
    }

    private func planeBasis(
        for plane: Plane3D,
        tolerance: ModelingTolerance
    ) throws -> (Vector3D, Vector3D) {
        let normal = try plane.normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        return (u, v)
    }

    private func cylinderBasis(
        for cylinder: Cylinder3D,
        tolerance: ModelingTolerance
    ) throws -> (Vector3D, Vector3D) {
        let axis = try cylinder.axis.normalized(tolerance: tolerance.distance)
        let helper = abs(axis.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(axis).normalized(tolerance: tolerance.distance)
        let v = axis.cross(u)
        return (u, v)
    }

    private static func analyticParameters(
        for point: Point3D,
        on surface: AnalyticSurface3D,
        tolerance: ModelingTolerance
    ) throws -> (u: Double, v: Double) {
        switch surface {
        case let .plane(origin, normal):
            let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
            let offset = point - origin
            return (offset.dot(basis.u), offset.dot(basis.v))
        case let .cylinder(origin, axis, _):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let offset = point - origin
            let height = offset.dot(axis)
            let radial = offset - axis * height
            return (normalizedAngle(atan2(radial.dot(basis.v), radial.dot(basis.u))), height)
        case let .cone(apex, axis, halfAngle):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let offset = point - apex
            let axialDistance = offset.dot(axis)
            let signedV = axialDistance / cos(halfAngle)
            let radial = offset - axis * axialDistance
            let direction = signedV >= 0.0 ? radial : -radial
            let u = direction.length > tolerance.distance
                ? normalizedAngle(atan2(direction.dot(basis.v), direction.dot(basis.u)))
                : 0.0
            return (u, signedV)
        case let .sphere(center, _):
            let direction = try (point - center).normalized(tolerance: tolerance.distance)
            let basis = try analyticOrthonormalBasis(.unitZ, tolerance: tolerance)
            return (
                normalizedAngle(atan2(direction.dot(basis.v), direction.dot(basis.u))),
                asin(min(max(direction.dot(.unitZ), -1.0), 1.0))
            )
        case let .torus(center, axis, majorRadius, _):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let offset = point - center
            let axialDistance = offset.dot(axis)
            let radial = offset - axis * axialDistance
            let radialLength = radial.length
            let radialDirection = radialLength > tolerance.distance
                ? try radial.normalized(tolerance: tolerance.distance)
                : basis.u
            return (
                radialLength > tolerance.distance
                    ? normalizedAngle(atan2(
                        radialDirection.dot(basis.v),
                        radialDirection.dot(basis.u)
                    ))
                    : 0.0,
                normalizedAngle(atan2(axialDistance, radialLength - majorRadius))
            )
        }
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        let period = Double.pi * 2.0
        let remainder = angle.truncatingRemainder(dividingBy: period)
        return remainder >= 0.0 ? remainder : remainder + period
    }

    private static func parameterDomain(_ domain: SurfaceParameterDomain) -> ParameterDomain {
        switch domain {
        case .unbounded:
            return .unbounded
        case let .bounded(lower, upper):
            return .closed(lower, upper)
        case let .periodic(period):
            return .periodic(period: period)
        }
    }
}

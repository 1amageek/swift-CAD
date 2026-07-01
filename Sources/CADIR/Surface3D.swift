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
    case bSpline(BSplineSurface3D)

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        switch self {
        case let .plane(plane):
            try plane.validate(tolerance: tolerance)
        case let .cylinder(cylinder):
            try cylinder.validate(tolerance: tolerance)
        case let .bSpline(surface):
            try surface.validate(tolerance: tolerance)
        }
    }

    public func point(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> Point3D {
        try validate(tolerance: tolerance)
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
        case let .bSpline(surface):
            return try surface.point(u: u, v: v, tolerance: tolerance)
        }
    }

    public func normal(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> Vector3D {
        try validate(tolerance: tolerance)
        guard try uDomain.contains(u, tolerance: tolerance),
              try vDomain.contains(v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
        switch self {
        case let .plane(plane):
            return try plane.normal.normalized(tolerance: tolerance.distance)
        case let .cylinder(cylinder):
            let (radialU, radialV) = try cylinderBasis(for: cylinder, tolerance: tolerance)
            let radial = radialU * cos(u) + radialV * sin(u)
            return try radial.normalized(tolerance: tolerance.distance)
        case let .bSpline(surface):
            return try surface.normal(u: u, v: v, tolerance: tolerance)
        }
    }

    public func differentialGeometry(
        atU u: Double,
        v: Double,
        tolerance: ModelingTolerance = .standard
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
        }
    }

    public var uDomain: ParameterDomain {
        switch self {
        case .plane:
            .unbounded
        case .cylinder:
            .periodic(period: Double.pi * 2.0)
        case .bSpline(let surface):
            surface.uDomain
        }
    }

    public var vDomain: ParameterDomain {
        switch self {
        case .plane, .cylinder:
            .unbounded
        case .bSpline(let surface):
            surface.vDomain
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case plane
        case cylinder
        case bSpline
    }

    private enum Kind: String, Codable {
        case plane
        case cylinder
        case bSpline
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
        case .bSpline:
            try container.validateOnlyExpectedKeys([.kind, .bSpline], in: decoder)
            self = .bSpline(try container.decode(BSplineSurface3D.self, forKey: .bSpline))
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
        case let .bSpline(surface):
            try container.encode(Kind.bSpline, forKey: .kind)
            try container.encode(surface, forKey: .bSpline)
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
}

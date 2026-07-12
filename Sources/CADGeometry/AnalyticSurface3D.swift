import Foundation
import CADCore

public enum AnalyticSurface3D: Codable, Equatable, Hashable, Sendable {
    public struct DifferentialGeometry: Codable, Equatable, Hashable, Sendable {
        public let position: Point3D
        public let tangentU: Vector3D
        public let tangentV: Vector3D
        public let secondDerivativeUU: Vector3D
        public let secondDerivativeUV: Vector3D
        public let secondDerivativeVV: Vector3D
        public let normal: Vector3D
        public let normalCurvatureU: Double
        public let normalCurvatureV: Double
        public let meanCurvature: Double
        public let gaussianCurvature: Double
        public let minimumPrincipalCurvature: Double
        public let maximumPrincipalCurvature: Double
        public let minimumPrincipalDirection: Vector3D
        public let maximumPrincipalDirection: Vector3D

        public init(
            position: Point3D,
            tangentU: Vector3D,
            tangentV: Vector3D,
            normal: Vector3D,
            secondDerivativeUU: Vector3D = .zero,
            secondDerivativeUV: Vector3D = .zero,
            secondDerivativeVV: Vector3D = .zero,
            normalCurvatureU: Double = 0.0,
            normalCurvatureV: Double = 0.0,
            meanCurvature: Double = 0.0,
            gaussianCurvature: Double = 0.0,
            minimumPrincipalCurvature: Double = 0.0,
            maximumPrincipalCurvature: Double = 0.0,
            minimumPrincipalDirection: Vector3D = .zero,
            maximumPrincipalDirection: Vector3D = .zero
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

    case plane(origin: Point3D, normal: Vector3D)
    case cylinder(origin: Point3D, axis: Vector3D, radius: Double)
    case cone(apex: Point3D, axis: Vector3D, halfAngle: Double)
    case sphere(center: Point3D, radius: Double)
    case torus(center: Point3D, axis: Vector3D, majorRadius: Double, minorRadius: Double)

    private enum CodingKeys: String, CodingKey {
        case kind
        case origin
        case normal
        case axis
        case radius
        case apex
        case halfAngle
        case center
        case majorRadius
        case minorRadius
    }

    private enum Kind: String, Codable {
        case plane
        case cylinder
        case cone
        case sphere
        case torus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .plane:
            self = .plane(
                origin: try container.decode(Point3D.self, forKey: .origin),
                normal: try container.decode(Vector3D.self, forKey: .normal)
            )
        case .cylinder:
            self = .cylinder(
                origin: try container.decode(Point3D.self, forKey: .origin),
                axis: try container.decode(Vector3D.self, forKey: .axis),
                radius: try container.decode(Double.self, forKey: .radius)
            )
        case .cone:
            self = .cone(
                apex: try container.decode(Point3D.self, forKey: .apex),
                axis: try container.decode(Vector3D.self, forKey: .axis),
                halfAngle: try container.decode(Double.self, forKey: .halfAngle)
            )
        case .sphere:
            self = .sphere(
                center: try container.decode(Point3D.self, forKey: .center),
                radius: try container.decode(Double.self, forKey: .radius)
            )
        case .torus:
            self = .torus(
                center: try container.decode(Point3D.self, forKey: .center),
                axis: try container.decode(Vector3D.self, forKey: .axis),
                majorRadius: try container.decode(Double.self, forKey: .majorRadius),
                minorRadius: try container.decode(Double.self, forKey: .minorRadius)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .plane(origin, normal):
            try container.encode(Kind.plane, forKey: .kind)
            try container.encode(origin, forKey: .origin)
            try container.encode(normal, forKey: .normal)
        case let .cylinder(origin, axis, radius):
            try container.encode(Kind.cylinder, forKey: .kind)
            try container.encode(origin, forKey: .origin)
            try container.encode(axis, forKey: .axis)
            try container.encode(radius, forKey: .radius)
        case let .cone(apex, axis, halfAngle):
            try container.encode(Kind.cone, forKey: .kind)
            try container.encode(apex, forKey: .apex)
            try container.encode(axis, forKey: .axis)
            try container.encode(halfAngle, forKey: .halfAngle)
        case let .sphere(center, radius):
            try container.encode(Kind.sphere, forKey: .kind)
            try container.encode(center, forKey: .center)
            try container.encode(radius, forKey: .radius)
        case let .torus(center, axis, majorRadius, minorRadius):
            try container.encode(Kind.torus, forKey: .kind)
            try container.encode(center, forKey: .center)
            try container.encode(axis, forKey: .axis)
            try container.encode(majorRadius, forKey: .majorRadius)
            try container.encode(minorRadius, forKey: .minorRadius)
        }
    }

    public var uDomain: SurfaceParameterDomain {
        switch self {
        case .plane:
            .unbounded
        case .cylinder, .cone, .sphere, .torus:
            .periodic(period: 2.0 * Double.pi)
        }
    }

    public var vDomain: SurfaceParameterDomain {
        switch self {
        case .plane, .cylinder, .cone:
            .unbounded
        case .sphere:
            .bounded(lower: -Double.pi * 0.5, upper: Double.pi * 0.5)
        case .torus:
            .periodic(period: 2.0 * Double.pi)
        }
    }

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        switch self {
        case let .plane(origin, normal):
            try origin.validate()
            try normal.validateUnitLength(tolerance: tolerance)
        case let .cylinder(origin, axis, radius):
            try origin.validate()
            try axis.validateUnitLength(tolerance: tolerance)
            try validateRadius(radius, tolerance: tolerance)
        case let .cone(apex, axis, halfAngle):
            try apex.validate()
            try axis.validateUnitLength(tolerance: tolerance)
            guard halfAngle.isFinite,
                  halfAngle > tolerance.angle,
                  halfAngle < Double.pi * 0.5 - tolerance.angle else {
                throw GeometryError.invalidAngle(halfAngle)
            }
        case let .sphere(center, radius):
            try center.validate()
            try validateRadius(radius, tolerance: tolerance)
        case let .torus(center, axis, majorRadius, minorRadius):
            try center.validate()
            try axis.validateUnitLength(tolerance: tolerance)
            try validateRadius(majorRadius, tolerance: tolerance)
            try validateRadius(minorRadius, tolerance: tolerance)
            guard majorRadius > minorRadius + tolerance.distance else {
                throw GeometryError.invalidRadius(minorRadius)
            }
        }
        try uDomain.validate()
        try vDomain.validate()
    }

    public func differentialGeometry(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> DifferentialGeometry {
        try validate(tolerance: tolerance)
        guard uDomain.contains(u, tolerance: tolerance.distance),
              vDomain.contains(v, tolerance: tolerance.distance) else {
            throw GeometryError.invalidDistance(u)
        }
        switch self {
        case let .plane(origin, normal):
            let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
            return DifferentialGeometry(
                position: origin + basis.u * u + basis.v * v,
                tangentU: basis.u,
                tangentV: basis.v,
                normal: normal
            )
        case let .cylinder(origin, axis, radius):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let radial = basis.u * cos(u) + basis.v * sin(u)
            let tangent = (-basis.u * sin(u) + basis.v * cos(u)) * radius
            return try makeDifferential(
                origin + radial * radius + axis * v,
                tangent,
                axis,
                secondDerivativeUU: -radial * radius,
                normal: radial,
                tolerance: tolerance
            )
        case let .cone(apex, axis, halfAngle):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let radial = basis.u * cos(u) + basis.v * sin(u)
            let tangent = (-basis.u * sin(u) + basis.v * cos(u)) * (v * sin(halfAngle))
            let tangentV = radial * sin(halfAngle) + axis * cos(halfAngle)
            let position = apex + axis * (v * cos(halfAngle)) + radial * (v * sin(halfAngle))
            return try makeDifferential(
                position,
                tangent,
                tangentV,
                secondDerivativeUU: -radial * (v * sin(halfAngle)),
                secondDerivativeUV: (-basis.u * sin(u) + basis.v * cos(u)) * sin(halfAngle),
                secondDerivativeVV: .zero,
                normal: try tangent.cross(tangentV).normalized(tolerance: tolerance.distance),
                tolerance: tolerance
            )
        case let .sphere(center, radius):
            let basis = try analyticOrthonormalBasis(Vector3D.unitZ, tolerance: tolerance)
            let radialU = basis.u * cos(u) + basis.v * sin(u)
            let tangentU = (-basis.u * sin(u) + basis.v * cos(u)) * (radius * cos(v))
            let radial = radialU * cos(v) + Vector3D.unitZ * sin(v)
            let tangentV = (-radialU * sin(v) + Vector3D.unitZ * cos(v)) * radius
            return try makeDifferential(
                center + radial * radius,
                tangentU,
                tangentV,
                secondDerivativeUU: -radialU * (radius * cos(v)),
                secondDerivativeUV: -(-basis.u * sin(u) + basis.v * cos(u)) * (radius * sin(v)),
                secondDerivativeVV: -radial * radius,
                normal: radial,
                tolerance: tolerance
            )
        case let .torus(center, axis, majorRadius, minorRadius):
            let basis = try analyticOrthonormalBasis(axis, tolerance: tolerance)
            let radial = basis.u * cos(u) + basis.v * sin(u)
            let tangent = -basis.u * sin(u) + basis.v * cos(u)
            let tube = radial * cos(v) + axis * sin(v)
            let tangentU = tangent * (majorRadius + minorRadius * cos(v))
            let tangentV = (-radial * sin(v) + axis * cos(v)) * minorRadius
            return try makeDifferential(
                center + radial * (majorRadius + minorRadius * cos(v)) + axis * (minorRadius * sin(v)),
                tangentU,
                tangentV,
                secondDerivativeUU: -radial * (majorRadius + minorRadius * cos(v)),
                secondDerivativeUV: tangent * (-minorRadius * sin(v)),
                secondDerivativeVV: (-radial * cos(v) - axis * sin(v)) * minorRadius,
                normal: tube,
                tolerance: tolerance
            )
        }
    }

    public func point(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> Point3D {
        try differentialGeometry(u: u, v: v, tolerance: tolerance).position
    }

    public func uvnFrame(
        u: Double,
        v: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> UVNFrame {
        let differential = try differentialGeometry(u: u, v: v, tolerance: tolerance)
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

    private func validateRadius(_ radius: Double, tolerance: ModelingTolerance) throws {
        guard radius.isFinite, radius > tolerance.distance else {
            throw GeometryError.invalidRadius(radius)
        }
    }

    private func makeDifferential(
        _ position: Point3D,
        _ tangentU: Vector3D,
        _ tangentV: Vector3D,
        secondDerivativeUU: Vector3D = .zero,
        secondDerivativeUV: Vector3D = .zero,
        secondDerivativeVV: Vector3D = .zero,
        normal: Vector3D? = nil,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        let surfaceNormal = try (normal ?? tangentU.cross(tangentV)).normalized(tolerance: tolerance.distance)
        let e = surfaceNormal.dot(secondDerivativeUU)
        let f = surfaceNormal.dot(secondDerivativeUV)
        let g = surfaceNormal.dot(secondDerivativeVV)
        let firstE = tangentU.dot(tangentU)
        let firstF = tangentU.dot(tangentV)
        let firstG = tangentV.dot(tangentV)
        let determinant = firstE * firstG - firstF * firstF
        let normalCurvatureU = firstE > tolerance.distance * tolerance.distance ? e / firstE : 0.0
        let normalCurvatureV = firstG > tolerance.distance * tolerance.distance ? g / firstG : 0.0
        let mean: Double
        let gaussian: Double
        if determinant > tolerance.distance * tolerance.distance {
            mean = (e * firstG - 2.0 * f * firstF + g * firstE) / (2.0 * determinant)
            gaussian = (e * g - f * f) / determinant
        } else {
            mean = 0.0
            gaussian = 0.0
        }
        let discriminant = max(0.0, mean * mean - gaussian)
        let root = sqrt(discriminant)
        let directionU = try tangentU.normalized(tolerance: tolerance.distance)
        let orthogonalV = tangentV - directionU * tangentV.dot(directionU)
        let directionV = try orthogonalV.normalized(tolerance: tolerance.distance)
        let (minimumDirection, maximumDirection) = principalDirections(
            tangentU: directionU,
            tangentV: directionV,
            firstFundamentalE: firstE,
            firstFundamentalF: firstF,
            firstFundamentalG: firstG,
            secondFundamentalE: e,
            secondFundamentalF: f,
            secondFundamentalG: g,
            tolerance: tolerance
        )
        return DifferentialGeometry(
            position: position,
            tangentU: tangentU,
            tangentV: tangentV,
            normal: surfaceNormal,
            secondDerivativeUU: secondDerivativeUU,
            secondDerivativeUV: secondDerivativeUV,
            secondDerivativeVV: secondDerivativeVV,
            normalCurvatureU: normalCurvatureU,
            normalCurvatureV: normalCurvatureV,
            meanCurvature: mean,
            gaussianCurvature: gaussian,
            minimumPrincipalCurvature: mean - root,
            maximumPrincipalCurvature: mean + root,
            minimumPrincipalDirection: minimumDirection,
            maximumPrincipalDirection: maximumDirection
        )
    }

    private func principalDirections(
        tangentU: Vector3D,
        tangentV: Vector3D,
        firstFundamentalE: Double,
        firstFundamentalF: Double,
        firstFundamentalG: Double,
        secondFundamentalE: Double,
        secondFundamentalF: Double,
        secondFundamentalG: Double,
        tolerance: ModelingTolerance
    ) -> (minimum: Vector3D, maximum: Vector3D) {
        let uLength = sqrt(max(firstFundamentalE, tolerance.distance * tolerance.distance))
        let vLengthSquared = firstFundamentalG - firstFundamentalF * firstFundamentalF / max(firstFundamentalE, tolerance.distance * tolerance.distance)
        let vLength = sqrt(max(vLengthSquared, tolerance.distance * tolerance.distance))
        let b11 = secondFundamentalE / (uLength * uLength)
        let b12 = (secondFundamentalF - secondFundamentalE * firstFundamentalF / max(firstFundamentalE, tolerance.distance * tolerance.distance)) / (uLength * vLength)
        let b22 = (
            secondFundamentalG
                - 2.0 * secondFundamentalF * firstFundamentalF / max(firstFundamentalE, tolerance.distance * tolerance.distance)
                + secondFundamentalE * firstFundamentalF * firstFundamentalF / max(firstFundamentalE * firstFundamentalE, tolerance.distance * tolerance.distance)
        ) / (vLength * vLength)
        let angle = 0.5 * atan2(2.0 * b12, b11 - b22)
        let maximum = tangentU * cos(angle) + tangentV * sin(angle)
        let minimum = tangentU * (-sin(angle)) + tangentV * cos(angle)
        return (minimum, maximum)
    }
}

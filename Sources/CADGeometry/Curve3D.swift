import Foundation
import CADCore

public enum Curve3D: Codable, Sendable, Hashable {
    public struct DifferentialGeometry: Codable, Sendable, Hashable {
        public var position: Point3D
        public var firstDerivative: Vector3D
        public var secondDerivative: Vector3D
        public var tangent: Vector3D
        public var curvatureVector: Vector3D
        public var curvature: Double

        public init(
            position: Point3D,
            firstDerivative: Vector3D,
            secondDerivative: Vector3D,
            tangent: Vector3D,
            curvatureVector: Vector3D,
            curvature: Double
        ) {
            self.position = position
            self.firstDerivative = firstDerivative
            self.secondDerivative = secondDerivative
            self.tangent = tangent
            self.curvatureVector = curvatureVector
            self.curvature = curvature
        }
    }

    case line(Line3D)
    case circle(Circle3D)
    case analytic(AnalyticCurve3D)
    case bSpline(BSplineCurve3D)
    case implicit(CertifiedImplicitIntersectionCurve)
    case surfaceLift(SurfaceLiftCurve3D)
    case certifiedIntersection(CertifiedIntersectionCurve3D)
    indirect case rigidImage(RigidImageCurve3D)
    indirect case affineImage(AffineImageCurve3D)

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        switch self {
        case let .line(line):
            try line.validate(tolerance: tolerance)
        case let .circle(circle):
            try circle.validate(tolerance: tolerance)
        case let .analytic(curve):
            try curve.validate(tolerance: tolerance)
        case let .bSpline(curve):
            try curve.validate(tolerance: tolerance)
        case let .implicit(curve):
            try curve.validate(tolerance: tolerance)
        case let .surfaceLift(curve):
            try curve.validate(tolerance: tolerance)
        case let .certifiedIntersection(curve):
            try curve.validate(tolerance: tolerance)
        case let .rigidImage(curve):
            try curve.validate(tolerance: tolerance)
        case let .affineImage(curve):
            try curve.validate(tolerance: tolerance)
        }
    }

    public var parameterDomain: ParameterDomain {
        switch self {
        case .line:
            .unbounded
        case .circle:
            .periodic(period: Double.pi * 2.0)
        case let .analytic(curve):
            Self.parameterDomain(curve.parameterDomain)
        case let .bSpline(curve):
            curve.domain
        case .implicit, .surfaceLift, .certifiedIntersection:
            .closed(0.0, 1.0)
        case let .rigidImage(curve):
            curve.parameterDomain
        case let .affineImage(curve):
            curve.parameterDomain
        }
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance) throws -> Point3D {
        try ValidatedCurve3D(self, tolerance: tolerance).point(at: parameter)
    }

    package func pointAssumingValid(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        switch self {
        case let .line(line):
            return line.origin + line.direction * parameter
        case let .circle(circle):
            let (u, v) = try circleOrthonormalBasis(
                circle.normal,
                tolerance: tolerance
            )
            return circle.center
                + (u * (circle.radius * cos(parameter)))
                + (v * (circle.radius * sin(parameter)))
        case let .analytic(curve):
            return try curve.differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            ).position
        case let .bSpline(curve):
            return try curve.pointAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
        case let .implicit(curve):
            return try curve.point(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
        case let .surfaceLift(curve):
            return try curve.pointAssumingValid(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
        case let .certifiedIntersection(curve):
            return try curve.point(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
        case let .rigidImage(curve):
            return try curve.pointAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
        case let .affineImage(curve):
            return try curve.pointAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
        }
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        try ValidatedCurve3D(self, tolerance: tolerance)
            .differentialGeometry(at: parameter)
    }

    package func differentialGeometryAssumingValid(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        switch self {
        case let .line(line):
            let firstDerivative = line.direction
            let secondDerivative = Vector3D.zero
            return DifferentialGeometry(
                position: line.origin + (line.direction * parameter),
                firstDerivative: firstDerivative,
                secondDerivative: secondDerivative,
                tangent: firstDerivative,
                curvatureVector: .zero,
                curvature: 0.0
            )
        case let .circle(circle):
            let (u, v) = try circleOrthonormalBasis(
                circle.normal,
                tolerance: tolerance
            )
            let firstDerivative = (u * (-circle.radius * sin(parameter))) +
                (v * (circle.radius * cos(parameter)))
            let secondDerivative = (u * (-circle.radius * cos(parameter))) +
                (v * (-circle.radius * sin(parameter)))
            return try Self.differentialGeometry(
                position: circle.center
                    + (u * (circle.radius * cos(parameter)))
                    + (v * (circle.radius * sin(parameter))),
                firstDerivative: firstDerivative,
                secondDerivative: secondDerivative,
                tolerance: tolerance
            )
        case let .analytic(curve):
            let geometry = try curve.differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
            return try Self.differentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tolerance: tolerance
            )
        case let .bSpline(curve):
            let geometry = try curve.differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tangent: geometry.tangent,
                curvatureVector: geometry.curvatureVector,
                curvature: geometry.curvature
            )
        case let .implicit(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
            return try Self.differentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tolerance: tolerance
            )
        case let .surfaceLift(curve):
            let geometry = try curve.differentialGeometryAssumingValid(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
            return try Self.differentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tolerance: tolerance
            )
        case let .certifiedIntersection(curve):
            let geometry = try curve.differential(
                atNormalizedFraction: parameter,
                tolerance: tolerance
            )
            return try Self.differentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tolerance: tolerance
            )
        case let .rigidImage(curve):
            return try curve.differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
        case let .affineImage(curve):
            return try curve.differentialGeometryAssumingValid(
                at: parameter,
                tolerance: tolerance
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case line
        case circle
        case analytic
        case bSpline
        case implicit
        case surfaceLift
        case certifiedIntersection
        case rigidImage
        case affineImage
    }

    private enum Kind: String, Codable {
        case line
        case circle
        case analytic
        case bSpline
        case implicit
        case surfaceLift
        case certifiedIntersection
        case rigidImage
        case affineImage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .line:
            try container.validateOnlyExpectedKeys([.kind, .line], in: decoder)
            self = .line(try container.decode(Line3D.self, forKey: .line))
        case .circle:
            try container.validateOnlyExpectedKeys([.kind, .circle], in: decoder)
            self = .circle(try container.decode(Circle3D.self, forKey: .circle))
        case .analytic:
            try container.validateOnlyExpectedKeys([.kind, .analytic], in: decoder)
            self = .analytic(try container.decode(AnalyticCurve3D.self, forKey: .analytic))
        case .bSpline:
            try container.validateOnlyExpectedKeys([.kind, .bSpline], in: decoder)
            self = .bSpline(try container.decode(BSplineCurve3D.self, forKey: .bSpline))
        case .implicit:
            try container.validateOnlyExpectedKeys([.kind, .implicit], in: decoder)
            self = .implicit(
                try container.decode(CertifiedImplicitIntersectionCurve.self, forKey: .implicit)
            )
        case .surfaceLift:
            try container.validateOnlyExpectedKeys([.kind, .surfaceLift], in: decoder)
            self = .surfaceLift(
                try container.decode(SurfaceLiftCurve3D.self, forKey: .surfaceLift)
            )
        case .certifiedIntersection:
            try container.validateOnlyExpectedKeys(
                [.kind, .certifiedIntersection],
                in: decoder
            )
            self = .certifiedIntersection(try container.decode(
                CertifiedIntersectionCurve3D.self,
                forKey: .certifiedIntersection
            ))
        case .rigidImage:
            try container.validateOnlyExpectedKeys([.kind, .rigidImage], in: decoder)
            self = .rigidImage(try container.decode(
                RigidImageCurve3D.self,
                forKey: .rigidImage
            ))
        case .affineImage:
            try container.validateOnlyExpectedKeys([.kind, .affineImage], in: decoder)
            self = .affineImage(try container.decode(
                AffineImageCurve3D.self,
                forKey: .affineImage
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .line(line):
            try container.encode(Kind.line, forKey: .kind)
            try container.encode(line, forKey: .line)
        case let .circle(circle):
            try container.encode(Kind.circle, forKey: .kind)
            try container.encode(circle, forKey: .circle)
        case let .analytic(curve):
            try container.encode(Kind.analytic, forKey: .kind)
            try container.encode(curve, forKey: .analytic)
        case let .bSpline(curve):
            try container.encode(Kind.bSpline, forKey: .kind)
            try container.encode(curve, forKey: .bSpline)
        case let .implicit(curve):
            try container.encode(Kind.implicit, forKey: .kind)
            try container.encode(curve, forKey: .implicit)
        case let .surfaceLift(curve):
            try container.encode(Kind.surfaceLift, forKey: .kind)
            try container.encode(curve, forKey: .surfaceLift)
        case let .certifiedIntersection(curve):
            try container.encode(Kind.certifiedIntersection, forKey: .kind)
            try container.encode(curve, forKey: .certifiedIntersection)
        case let .rigidImage(curve):
            try container.encode(Kind.rigidImage, forKey: .kind)
            try container.encode(curve, forKey: .rigidImage)
        case let .affineImage(curve):
            try container.encode(Kind.affineImage, forKey: .kind)
            try container.encode(curve, forKey: .affineImage)
        }
    }

    private static func differentialGeometry(
        position: Point3D,
        firstDerivative: Vector3D,
        secondDerivative: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        let tangent = try firstDerivative.normalized(tolerance: tolerance.distance)
        let speed = firstDerivative.length
        let tangentialAcceleration = tangent * secondDerivative.dot(tangent)
        let curvatureVector = (secondDerivative - tangentialAcceleration) / (speed * speed)
        return DifferentialGeometry(
            position: position,
            firstDerivative: firstDerivative,
            secondDerivative: secondDerivative,
            tangent: tangent,
            curvatureVector: curvatureVector,
            curvature: curvatureVector.length
        )
    }

    private static func parameterDomain(_ domain: CurveParameterDomain) -> ParameterDomain {
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

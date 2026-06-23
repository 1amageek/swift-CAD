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
    case bSpline(BSplineCurve3D)

    public func validate(tolerance: ModelingTolerance = .standard) throws {
        try tolerance.validate()
        switch self {
        case let .line(line):
            try line.validate(tolerance: tolerance)
        case let .circle(circle):
            try circle.validate(tolerance: tolerance)
        case let .bSpline(curve):
            try curve.validate(tolerance: tolerance)
        }
    }

    public var parameterDomain: ParameterDomain {
        switch self {
        case .line:
            .unbounded
        case .circle:
            .periodic(period: Double.pi * 2.0)
        case let .bSpline(curve):
            curve.domain
        }
    }

    public func point(at parameter: Double, tolerance: ModelingTolerance = .standard) throws -> Point3D {
        try differentialGeometry(at: parameter, tolerance: tolerance).position
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> DifferentialGeometry {
        try validate(tolerance: tolerance)
        guard try parameterDomain.contains(parameter, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
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
            let (u, v) = try circleBasis(for: circle, tolerance: tolerance)
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
        case let .bSpline(curve):
            let geometry = try curve.differentialGeometry(at: parameter, tolerance: tolerance)
            return DifferentialGeometry(
                position: geometry.position,
                firstDerivative: geometry.firstDerivative,
                secondDerivative: geometry.secondDerivative,
                tangent: geometry.tangent,
                curvatureVector: geometry.curvatureVector,
                curvature: geometry.curvature
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case line
        case circle
        case bSpline
    }

    private enum Kind: String, Codable {
        case line
        case circle
        case bSpline
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
        case .bSpline:
            try container.validateOnlyExpectedKeys([.kind, .bSpline], in: decoder)
            self = .bSpline(try container.decode(BSplineCurve3D.self, forKey: .bSpline))
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
        case let .bSpline(curve):
            try container.encode(Kind.bSpline, forKey: .kind)
            try container.encode(curve, forKey: .bSpline)
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

    private func circleBasis(for circle: Circle3D, tolerance: ModelingTolerance) throws -> (Vector3D, Vector3D) {
        let normal = try circle.normal.normalized(tolerance: tolerance.distance)
        let helper = abs(normal.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
        let u = try helper.cross(normal).normalized(tolerance: tolerance.distance)
        let v = normal.cross(u)
        return (u, v)
    }
}

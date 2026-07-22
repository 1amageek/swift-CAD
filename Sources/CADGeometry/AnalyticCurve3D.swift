import Foundation
import CADCore

public enum AnalyticCurve3D: Codable, Equatable, Hashable, Sendable {
    public struct DifferentialGeometry: Codable, Equatable, Hashable, Sendable {
        public let position: Point3D
        public let firstDerivative: Vector3D
        public let secondDerivative: Vector3D
        public let tangent: Vector3D
        public let curvature: Double

        public init(
            position: Point3D,
            firstDerivative: Vector3D,
            secondDerivative: Vector3D,
            tangent: Vector3D,
            curvature: Double
        ) {
            self.position = position
            self.firstDerivative = firstDerivative
            self.secondDerivative = secondDerivative
            self.tangent = tangent
            self.curvature = curvature
        }
    }

    case line(origin: Point3D, direction: Vector3D)
    case circle(center: Point3D, normal: Vector3D, radius: Double)
    case arc(
        center: Point3D,
        normal: Vector3D,
        radius: Double,
        startAngle: Double,
        endAngle: Double
    )
    case ellipse(
        center: Point3D,
        normal: Vector3D,
        majorAxis: Vector3D,
        majorRadius: Double,
        minorRadius: Double
    )
    case hyperbola(Hyperbola3D)
    case parabola(Parabola3D)
    case planeTorus(CertifiedPlaneTorusIntersectionCurve)

    private enum CodingKeys: String, CodingKey {
        case kind
        case origin
        case direction
        case center
        case normal
        case radius
        case startAngle
        case endAngle
        case majorAxis
        case majorRadius
        case minorRadius
        case hyperbola
        case parabola
        case planeTorus
    }

    private enum Kind: String, Codable {
        case line
        case circle
        case arc
        case ellipse
        case hyperbola
        case parabola
        case planeTorus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .line:
            self = .line(
                origin: try container.decode(Point3D.self, forKey: .origin),
                direction: try container.decode(Vector3D.self, forKey: .direction)
            )
        case .circle:
            self = .circle(
                center: try container.decode(Point3D.self, forKey: .center),
                normal: try container.decode(Vector3D.self, forKey: .normal),
                radius: try container.decode(Double.self, forKey: .radius)
            )
        case .arc:
            self = .arc(
                center: try container.decode(Point3D.self, forKey: .center),
                normal: try container.decode(Vector3D.self, forKey: .normal),
                radius: try container.decode(Double.self, forKey: .radius),
                startAngle: try container.decode(Double.self, forKey: .startAngle),
                endAngle: try container.decode(Double.self, forKey: .endAngle)
            )
        case .ellipse:
            self = .ellipse(
                center: try container.decode(Point3D.self, forKey: .center),
                normal: try container.decode(Vector3D.self, forKey: .normal),
                majorAxis: try container.decode(Vector3D.self, forKey: .majorAxis),
                majorRadius: try container.decode(Double.self, forKey: .majorRadius),
                minorRadius: try container.decode(Double.self, forKey: .minorRadius)
            )
        case .hyperbola:
            self = .hyperbola(try container.decode(Hyperbola3D.self, forKey: .hyperbola))
        case .parabola:
            self = .parabola(try container.decode(Parabola3D.self, forKey: .parabola))
        case .planeTorus:
            self = .planeTorus(try container.decode(
                CertifiedPlaneTorusIntersectionCurve.self,
                forKey: .planeTorus
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .line(origin, direction):
            try container.encode(Kind.line, forKey: .kind)
            try container.encode(origin, forKey: .origin)
            try container.encode(direction, forKey: .direction)
        case let .circle(center, normal, radius):
            try container.encode(Kind.circle, forKey: .kind)
            try container.encode(center, forKey: .center)
            try container.encode(normal, forKey: .normal)
            try container.encode(radius, forKey: .radius)
        case let .arc(center, normal, radius, startAngle, endAngle):
            try container.encode(Kind.arc, forKey: .kind)
            try container.encode(center, forKey: .center)
            try container.encode(normal, forKey: .normal)
            try container.encode(radius, forKey: .radius)
            try container.encode(startAngle, forKey: .startAngle)
            try container.encode(endAngle, forKey: .endAngle)
        case let .ellipse(center, normal, majorAxis, majorRadius, minorRadius):
            try container.encode(Kind.ellipse, forKey: .kind)
            try container.encode(center, forKey: .center)
            try container.encode(normal, forKey: .normal)
            try container.encode(majorAxis, forKey: .majorAxis)
            try container.encode(majorRadius, forKey: .majorRadius)
            try container.encode(minorRadius, forKey: .minorRadius)
        case let .hyperbola(curve):
            try container.encode(Kind.hyperbola, forKey: .kind)
            try container.encode(curve, forKey: .hyperbola)
        case let .parabola(curve):
            try container.encode(Kind.parabola, forKey: .kind)
            try container.encode(curve, forKey: .parabola)
        case let .planeTorus(curve):
            try container.encode(Kind.planeTorus, forKey: .kind)
            try container.encode(curve, forKey: .planeTorus)
        }
    }

    public var parameterDomain: CurveParameterDomain {
        switch self {
        case .line, .hyperbola, .parabola:
            .unbounded
        case .circle, .ellipse, .planeTorus:
            .periodic(period: 2.0 * Double.pi)
        case let .arc(_, _, _, startAngle, endAngle):
            .bounded(lower: startAngle, upper: endAngle)
        }
    }

    public func validate(tolerance: ModelingTolerance) throws {
        try tolerance.validate()
        switch self {
        case let .line(origin, direction):
            try origin.validate()
            try direction.validateUnitLength(tolerance: tolerance)
        case let .circle(center, normal, radius):
            try center.validate()
            try normal.validateUnitLength(tolerance: tolerance)
            try validateRadius(radius, tolerance: tolerance)
        case let .arc(center, normal, radius, startAngle, endAngle):
            try center.validate()
            try normal.validateUnitLength(tolerance: tolerance)
            try validateRadius(radius, tolerance: tolerance)
            guard startAngle.isFinite, endAngle.isFinite, endAngle > startAngle else {
                throw GeometryError.invalidAngle(endAngle - startAngle)
            }
            guard endAngle - startAngle <= 2.0 * Double.pi + tolerance.angle else {
                throw GeometryError.invalidAngle(endAngle - startAngle)
            }
        case let .ellipse(center, normal, majorAxis, majorRadius, minorRadius):
            try center.validate()
            try normal.validateUnitLength(tolerance: tolerance)
            try majorAxis.validateUnitLength(tolerance: tolerance)
            guard abs(normal.dot(majorAxis)) <= tolerance.angle else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "Ellipse major axis must be perpendicular to its normal."
                )
            }
            try validateRadius(majorRadius, tolerance: tolerance)
            try validateRadius(minorRadius, tolerance: tolerance)
            guard majorRadius >= minorRadius else {
                throw GeometryError.invalidRadius(minorRadius)
            }
        case let .hyperbola(curve):
            try curve.validate(tolerance: tolerance)
        case let .parabola(curve):
            try curve.validate(tolerance: tolerance)
        case let .planeTorus(curve):
            try curve.validate(tolerance: tolerance)
        }
        try parameterDomain.validate()
    }

    public func differentialGeometry(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        try validate(tolerance: tolerance)
        guard parameter.isFinite else {
            throw GeometryError.invalidDistance(parameter)
        }
        switch self {
        case let .line(origin, direction):
            return DifferentialGeometry(
                position: origin + direction * parameter,
                firstDerivative: direction,
                secondDerivative: .zero,
                tangent: direction,
                curvature: 0.0
            )
        case let .circle(center, normal, radius):
            return try circularDifferential(
                center: center,
                normal: normal,
                radius: radius,
                parameter: parameter,
                tolerance: tolerance
            )
        case let .arc(center, normal, radius, startAngle, endAngle):
            guard parameterDomain.contains(parameter, tolerance: tolerance.angle) else {
                throw GeometryError.invalidDistance(parameter)
            }
            _ = startAngle
            _ = endAngle
            return try circularDifferential(
                center: center,
                normal: normal,
                radius: radius,
                parameter: parameter,
                tolerance: tolerance
            )
        case let .ellipse(center, normal, majorAxis, majorRadius, minorRadius):
            let minorAxis = try normal.cross(majorAxis).normalized(tolerance: tolerance.distance)
            let position = center
                + majorAxis * (majorRadius * cos(parameter))
                + minorAxis * (minorRadius * sin(parameter))
            let first = -majorAxis * (majorRadius * sin(parameter))
                + minorAxis * (minorRadius * cos(parameter))
            let second = -majorAxis * (majorRadius * cos(parameter))
                - minorAxis * (minorRadius * sin(parameter))
            return try Self.makeDifferential(position, first, second, tolerance: tolerance)
        case let .hyperbola(curve):
            return try curve.differentialGeometry(at: parameter, tolerance: tolerance)
        case let .parabola(curve):
            return try curve.differentialGeometry(at: parameter, tolerance: tolerance)
        case let .planeTorus(curve):
            let geometry = try curve.differentialGeometry(
                at: parameter,
                tolerance: tolerance
            )
            return try Self.makeDifferential(
                geometry.position,
                geometry.firstDerivative,
                geometry.secondDerivative,
                tolerance: tolerance
            )
        }
    }

    public func point(
        at parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> Point3D {
        try differentialGeometry(at: parameter, tolerance: tolerance).position
    }

    private func circularDifferential(
        center: Point3D,
        normal: Vector3D,
        radius: Double,
        parameter: Double,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        let basis = try analyticOrthonormalBasis(normal, tolerance: tolerance)
        let radial = basis.u * cos(parameter) + basis.v * sin(parameter)
        let first = (-basis.u * sin(parameter) + basis.v * cos(parameter)) * radius
        let second = -radial * radius
        return try Self.makeDifferential(
            center + radial * radius,
            first,
            second,
            tolerance: tolerance
        )
    }

    static func makeDifferentialGeometry(
        position: Point3D,
        firstDerivative: Vector3D,
        secondDerivative: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        try makeDifferential(
            position,
            firstDerivative,
            secondDerivative,
            tolerance: tolerance
        )
    }

    private static func makeDifferential(
        _ position: Point3D,
        _ first: Vector3D,
        _ second: Vector3D,
        tolerance: ModelingTolerance
    ) throws -> DifferentialGeometry {
        let tangent = try first.normalized(tolerance: tolerance.distance)
        let curvature = first.cross(second).length / pow(first.length, 3.0)
        return DifferentialGeometry(
            position: position,
            firstDerivative: first,
            secondDerivative: second,
            tangent: tangent,
            curvature: curvature
        )
    }

    private func validateRadius(_ radius: Double, tolerance: ModelingTolerance) throws {
        guard radius.isFinite, radius > tolerance.distance else {
            throw GeometryError.invalidRadius(radius)
        }
    }
}

import Foundation
import CADCore

public struct SurfaceParameter: Codable, Sendable, Hashable {
    public var u: Double
    public var v: Double

    public init(u: Double, v: Double) {
        self.u = u
        self.v = v
    }

    public func validate() throws {
        guard u.isFinite, v.isFinite else {
            throw GeometryError.invalidCoordinate(u.isFinite ? v : u)
        }
    }

    public func isApproximatelyEqual(to other: SurfaceParameter, tolerance: Double) -> Bool {
        hypot(u - other.u, v - other.v) <= tolerance
    }
}

public enum SurfaceParameterBoundary: String, Codable, Sendable, Hashable, CaseIterable {
    case uLower
    case uUpper
    case vLower
    case vUpper
}

public enum SurfaceParameterCurveDirection: String, Codable, Sendable, Hashable {
    case forward
    case reversed
}

public enum SurfaceParameterCurve: Codable, Sendable, Hashable {
    case affine(
        origin: Point2D,
        direction: Point2D,
        startParameter: Double,
        endParameter: Double
    )
    case constantU(u: Double, vStart: Double, vEnd: Double)
    case constantV(v: Double, uStart: Double, uEnd: Double)
    case harmonic(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        startParameter: Double,
        endParameter: Double
    )
    case sphericalGreatCircle(
        cosine: Vector3D,
        sine: Vector3D,
        startParameter: Double,
        endParameter: Double
    )
    case polyline([SurfaceParameter])
    case bSpline(BSplineCurve2D)

    public static func boundary(
        _ boundary: SurfaceParameterBoundary,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        let uBounds = try closedBounds(surface.uDomain, tolerance: tolerance)
        let vBounds = try closedBounds(surface.vDomain, tolerance: tolerance)
        switch boundary {
        case .uLower:
            return .constantU(u: uBounds.lower, vStart: vBounds.lower, vEnd: vBounds.upper)
        case .uUpper:
            return .constantU(u: uBounds.upper, vStart: vBounds.lower, vEnd: vBounds.upper)
        case .vLower:
            return .constantV(v: vBounds.lower, uStart: uBounds.lower, uEnd: uBounds.upper)
        case .vUpper:
            return .constantV(v: vBounds.upper, uStart: uBounds.lower, uEnd: uBounds.upper)
        }
    }

    public func validate(
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try tolerance.validate()
        switch self {
        case let .affine(origin, direction, startParameter, endParameter):
            let values = [
                origin.x, origin.y, direction.x, direction.y,
                startParameter, endParameter,
            ]
            guard values.allSatisfy(\.isFinite),
                  hypot(direction.x, direction.y) > Double.ulpOfOne,
                  endParameter - startParameter > tolerance.distance else {
                throw GeometryError.invalidDistance(endParameter - startParameter)
            }
            for parameter in [startParameter, endParameter] {
                try validateParameter(
                    affineParameter(origin: origin, direction: direction, parameter: parameter),
                    on: surface,
                    tolerance: tolerance
                )
            }
        case let .constantU(u, vStart, vEnd):
            try validateParameter(SurfaceParameter(u: u, v: vStart), on: surface, tolerance: tolerance)
            try validateParameter(SurfaceParameter(u: u, v: vEnd), on: surface, tolerance: tolerance)
            guard abs(vEnd - vStart) > Double.ulpOfOne else {
                throw GeometryError.invalidDistance(vEnd - vStart)
            }
        case let .constantV(v, uStart, uEnd):
            try validateParameter(SurfaceParameter(u: uStart, v: v), on: surface, tolerance: tolerance)
            try validateParameter(SurfaceParameter(u: uEnd, v: v), on: surface, tolerance: tolerance)
            guard abs(uEnd - uStart) > Double.ulpOfOne else {
                throw GeometryError.invalidDistance(uEnd - uStart)
            }
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            let values = [
                center.x, center.y, cosine.x, cosine.y, sine.x, sine.y,
                startParameter, endParameter,
            ]
            guard values.allSatisfy(\.isFinite),
                  abs(endParameter - startParameter) > tolerance.angle,
                  abs(endParameter - startParameter) <= 2.0 * Double.pi + tolerance.angle else {
                throw GeometryError.invalidDistance(endParameter - startParameter)
            }
            for index in 0...16 {
                let fraction = Double(index) / 16.0
                try validateParameter(
                    harmonicParameter(
                        center: center,
                        cosine: cosine,
                        sine: sine,
                        parameter: interpolated(
                            startParameter,
                            endParameter,
                            fraction: fraction
                        )
                    ),
                    on: surface,
                    tolerance: tolerance
                )
            }
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            guard case .analytic(.sphere) = surface else {
                throw GeometryError.invalidDistance(endParameter - startParameter)
            }
            try cosine.validateUnitLength(tolerance: tolerance)
            try sine.validateUnitLength(tolerance: tolerance)
            guard abs(cosine.dot(sine)) <= tolerance.angle,
                  startParameter.isFinite,
                  endParameter.isFinite,
                  abs(endParameter - startParameter) > tolerance.angle,
                  abs(endParameter - startParameter) <= 2.0 * Double.pi + tolerance.angle else {
                throw GeometryError.invalidDistance(endParameter - startParameter)
            }
            for index in 0...16 {
                let fraction = Double(index) / 16.0
                try validateParameter(
                    sphericalParameter(
                        cosine: cosine,
                        sine: sine,
                        parameter: interpolated(startParameter, endParameter, fraction: fraction),
                        startParameter: startParameter,
                        endParameter: endParameter
                    ),
                    on: surface,
                    tolerance: tolerance
                )
            }
        case let .polyline(points):
            guard points.count >= 2 else {
                throw GeometryError.invalidDistance(Double(points.count))
            }
            var totalLength = 0.0
            var previous: SurfaceParameter?
            for point in points {
                try validateParameter(point, on: surface, tolerance: tolerance)
                if let previous {
                    totalLength += parameterDistance(from: previous, to: point)
                }
                previous = point
            }
            guard totalLength > Double.ulpOfOne else {
                throw GeometryError.invalidDistance(totalLength)
            }
        case let .bSpline(curve):
            try curve.validate(tolerance: tolerance)
            for controlPoint in curve.controlPoints {
                try validateParameter(
                    SurfaceParameter(u: controlPoint.x, v: controlPoint.y),
                    on: surface,
                    tolerance: tolerance
                )
            }
        }
    }

    public func parameter(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.distance,
              fraction <= 1.0 + tolerance.distance else {
            throw GeometryError.invalidDistance(fraction)
        }
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        switch self {
        case let .affine(origin, direction, startParameter, endParameter):
            return affineParameter(
                origin: origin,
                direction: direction,
                parameter: interpolated(startParameter, endParameter, fraction: clampedFraction)
            )
        case let .constantU(u, vStart, vEnd):
            return SurfaceParameter(u: u, v: interpolated(vStart, vEnd, fraction: clampedFraction))
        case let .constantV(v, uStart, uEnd):
            return SurfaceParameter(u: interpolated(uStart, uEnd, fraction: clampedFraction), v: v)
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return harmonicParameter(
                center: center,
                cosine: cosine,
                sine: sine,
                parameter: interpolated(
                    startParameter,
                    endParameter,
                    fraction: clampedFraction
                )
            )
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return sphericalParameter(
                cosine: cosine,
                sine: sine,
                parameter: interpolated(startParameter, endParameter, fraction: clampedFraction),
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .polyline(points):
            return try polylineParameter(points: points, fraction: clampedFraction)
        case let .bSpline(curve):
            let bounds = try Self.closedBounds(curve.domain, tolerance: tolerance)
            let parameter = interpolated(bounds.lower, bounds.upper, fraction: clampedFraction)
            let point = try curve.point(at: parameter, tolerance: tolerance)
            return SurfaceParameter(u: point.x, v: point.y)
        }
    }

    public func parameter(
        atCurveParameter parameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        try tolerance.validate()
        guard parameter.isFinite else {
            throw GeometryError.invalidDistance(parameter)
        }
        switch self {
        case let .affine(origin, direction, _, _):
            return affineParameter(origin: origin, direction: direction, parameter: parameter)
        case let .harmonic(center, cosine, sine, _, _):
            return harmonicParameter(
                center: center,
                cosine: cosine,
                sine: sine,
                parameter: parameter
            )
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return sphericalParameter(
                cosine: cosine,
                sine: sine,
                parameter: parameter,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .bSpline(curve):
            let point = try curve.point(at: parameter, tolerance: tolerance)
            return SurfaceParameter(u: point.x, v: point.y)
        case .constantU, .constantV, .polyline:
            return try self.parameter(
                atNormalizedFraction: normalizedFraction(
                    parameter,
                    domain: curveDomain,
                    tolerance: tolerance
                ),
                tolerance: tolerance
            )
        }
    }

    public func startParameter(tolerance: ModelingTolerance) throws -> SurfaceParameter {
        try parameter(atNormalizedFraction: 0.0, tolerance: tolerance)
    }

    public func endParameter(tolerance: ModelingTolerance) throws -> SurfaceParameter {
        try parameter(atNormalizedFraction: 1.0, tolerance: tolerance)
    }

    public func reversed(tolerance: ModelingTolerance) throws -> SurfaceParameterCurve {
        try tolerance.validate()
        switch self {
        case let .affine(origin, direction, startParameter, endParameter):
            return .affine(
                origin: Point2D(
                    x: origin.x + direction.x * (startParameter + endParameter),
                    y: origin.y + direction.y * (startParameter + endParameter)
                ),
                direction: Point2D(x: -direction.x, y: -direction.y),
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .constantU(u, vStart, vEnd):
            return .constantU(u: u, vStart: vEnd, vEnd: vStart)
        case let .constantV(v, uStart, uEnd):
            return .constantV(v: v, uStart: uEnd, uEnd: uStart)
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return .harmonic(
                center: center,
                cosine: cosine,
                sine: sine,
                startParameter: endParameter,
                endParameter: startParameter
            )
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return .sphericalGreatCircle(
                cosine: cosine,
                sine: sine,
                startParameter: endParameter,
                endParameter: startParameter
            )
        case let .polyline(points):
            return .polyline(Array(points.reversed()))
        case let .bSpline(curve):
            return .bSpline(try curve.reversed(tolerance: tolerance))
        }
    }

    public func trimmed(
        from startParameter: Double,
        to endParameter: Double,
        curveDomain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        try tolerance.validate()
        guard startParameter.isFinite,
              endParameter.isFinite,
              endParameter - startParameter > max(tolerance.angle, tolerance.distance),
              try curveDomain.containsSpan(
                  from: startParameter,
                  to: endParameter,
                  tolerance: tolerance
              ) else {
            throw GeometryError.invalidDistance(endParameter - startParameter)
        }
        switch self {
        case let .affine(origin, direction, _, _):
            return .affine(
                origin: origin,
                direction: direction,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .constantU(u, _, _):
            let start = try parameter(
                atCurveParameter: startParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            )
            let end = try parameter(
                atCurveParameter: endParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            )
            return .constantU(u: u, vStart: start.v, vEnd: end.v)
        case let .constantV(v, _, _):
            let start = try parameter(
                atCurveParameter: startParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            )
            let end = try parameter(
                atCurveParameter: endParameter,
                curveDomain: curveDomain,
                tolerance: tolerance
            )
            return .constantV(v: v, uStart: start.u, uEnd: end.u)
        case let .harmonic(center, cosine, sine, _, _):
            return .harmonic(
                center: center,
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case let .sphericalGreatCircle(cosine, sine, _, _):
            return .sphericalGreatCircle(
                cosine: cosine,
                sine: sine,
                startParameter: startParameter,
                endParameter: endParameter
            )
        case .polyline:
            throw KernelError(
                phase: .geometry,
                code: .unsupportedCapability,
                tolerance: tolerance,
                message: "Exact trimming of an arc-length polyline pcurve requires an explicit parameter map."
            )
        case let .bSpline(curve):
            return .bSpline(try curve.trimmed(
                from: startParameter,
                to: endParameter,
                tolerance: tolerance
            ))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case origin
        case direction
        case u
        case v
        case uStart
        case uEnd
        case vStart
        case vEnd
        case center
        case cosine
        case sine
        case startParameter
        case endParameter
        case points
        case bSpline
        case sphericalGreatCircle
    }

    private enum Kind: String, Codable {
        case affine
        case constantU
        case constantV
        case harmonic
        case polyline
        case bSpline
        case sphericalGreatCircle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .affine:
            try container.validateOnlyExpectedKeys(
                [.kind, .origin, .direction, .startParameter, .endParameter],
                in: decoder
            )
            self = .affine(
                origin: try container.decode(Point2D.self, forKey: .origin),
                direction: try container.decode(Point2D.self, forKey: .direction),
                startParameter: try container.decode(Double.self, forKey: .startParameter),
                endParameter: try container.decode(Double.self, forKey: .endParameter)
            )
        case .constantU:
            try container.validateOnlyExpectedKeys([.kind, .u, .vStart, .vEnd], in: decoder)
            self = .constantU(
                u: try container.decode(Double.self, forKey: .u),
                vStart: try container.decode(Double.self, forKey: .vStart),
                vEnd: try container.decode(Double.self, forKey: .vEnd)
            )
        case .constantV:
            try container.validateOnlyExpectedKeys([.kind, .v, .uStart, .uEnd], in: decoder)
            self = .constantV(
                v: try container.decode(Double.self, forKey: .v),
                uStart: try container.decode(Double.self, forKey: .uStart),
                uEnd: try container.decode(Double.self, forKey: .uEnd)
            )
        case .harmonic:
            try container.validateOnlyExpectedKeys(
                [.kind, .center, .cosine, .sine, .startParameter, .endParameter],
                in: decoder
            )
            self = .harmonic(
                center: try container.decode(Point2D.self, forKey: .center),
                cosine: try container.decode(Point2D.self, forKey: .cosine),
                sine: try container.decode(Point2D.self, forKey: .sine),
                startParameter: try container.decode(Double.self, forKey: .startParameter),
                endParameter: try container.decode(Double.self, forKey: .endParameter)
            )
        case .polyline:
            try container.validateOnlyExpectedKeys([.kind, .points], in: decoder)
            self = .polyline(try container.decode([SurfaceParameter].self, forKey: .points))
        case .bSpline:
            try container.validateOnlyExpectedKeys([.kind, .bSpline], in: decoder)
            self = .bSpline(try container.decode(BSplineCurve2D.self, forKey: .bSpline))
        case .sphericalGreatCircle:
            try container.validateOnlyExpectedKeys(
                [.kind, .cosine, .sine, .startParameter, .endParameter],
                in: decoder
            )
            self = .sphericalGreatCircle(
                cosine: try container.decode(Vector3D.self, forKey: .cosine),
                sine: try container.decode(Vector3D.self, forKey: .sine),
                startParameter: try container.decode(Double.self, forKey: .startParameter),
                endParameter: try container.decode(Double.self, forKey: .endParameter)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .affine(origin, direction, startParameter, endParameter):
            try container.encode(Kind.affine, forKey: .kind)
            try container.encode(origin, forKey: .origin)
            try container.encode(direction, forKey: .direction)
            try container.encode(startParameter, forKey: .startParameter)
            try container.encode(endParameter, forKey: .endParameter)
        case let .constantU(u, vStart, vEnd):
            try container.encode(Kind.constantU, forKey: .kind)
            try container.encode(u, forKey: .u)
            try container.encode(vStart, forKey: .vStart)
            try container.encode(vEnd, forKey: .vEnd)
        case let .constantV(v, uStart, uEnd):
            try container.encode(Kind.constantV, forKey: .kind)
            try container.encode(v, forKey: .v)
            try container.encode(uStart, forKey: .uStart)
            try container.encode(uEnd, forKey: .uEnd)
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            try container.encode(Kind.harmonic, forKey: .kind)
            try container.encode(center, forKey: .center)
            try container.encode(cosine, forKey: .cosine)
            try container.encode(sine, forKey: .sine)
            try container.encode(startParameter, forKey: .startParameter)
            try container.encode(endParameter, forKey: .endParameter)
        case let .polyline(points):
            try container.encode(Kind.polyline, forKey: .kind)
            try container.encode(points, forKey: .points)
        case let .bSpline(curve):
            try container.encode(Kind.bSpline, forKey: .kind)
            try container.encode(curve, forKey: .bSpline)
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            try container.encode(Kind.sphericalGreatCircle, forKey: .kind)
            try container.encode(cosine, forKey: .cosine)
            try container.encode(sine, forKey: .sine)
            try container.encode(startParameter, forKey: .startParameter)
            try container.encode(endParameter, forKey: .endParameter)
        }
    }

    private static func closedBounds(
        _ domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> (lower: Double, upper: Double) {
        try domain.validate(tolerance: tolerance)
        guard case let .closed(lower, upper) = domain else {
            throw GeometryError.invalidDistance(0.0)
        }
        return (lower, upper)
    }

    private func validateParameter(
        _ parameter: SurfaceParameter,
        on surface: Surface3D,
        tolerance: ModelingTolerance
    ) throws {
        try parameter.validate()
        guard try surface.uDomain.contains(parameter.u, tolerance: tolerance),
              try surface.vDomain.contains(parameter.v, tolerance: tolerance) else {
            throw GeometryError.invalidDistance(0.0)
        }
    }

    private func polylineParameter(points: [SurfaceParameter], fraction: Double) throws -> SurfaceParameter {
        guard let first = points.first,
              let last = points.last else {
            throw GeometryError.invalidDistance(Double(points.count))
        }
        guard fraction > 0.0 else {
            return first
        }
        guard fraction < 1.0 else {
            return last
        }

        var segmentLengths: [Double] = []
        var totalLength = 0.0
        for index in 1..<points.count {
            let length = parameterDistance(from: points[index - 1], to: points[index])
            segmentLengths.append(length)
            totalLength += length
        }
        guard totalLength > Double.ulpOfOne else {
            throw GeometryError.invalidDistance(totalLength)
        }
        let targetLength = totalLength * fraction
        var accumulatedLength = 0.0
        for index in 0..<segmentLengths.count {
            let nextLength = accumulatedLength + segmentLengths[index]
            if targetLength <= nextLength || index == segmentLengths.count - 1 {
                let segmentFraction = (targetLength - accumulatedLength) / segmentLengths[index]
                return SurfaceParameter(
                    u: interpolated(points[index].u, points[index + 1].u, fraction: segmentFraction),
                    v: interpolated(points[index].v, points[index + 1].v, fraction: segmentFraction)
                )
            }
            accumulatedLength = nextLength
        }
        return last
    }

    private func sphericalParameter(
        cosine: Vector3D,
        sine: Vector3D,
        parameter: Double,
        startParameter: Double,
        endParameter: Double
    ) -> SurfaceParameter {
        let radial = cosine * cos(parameter) + sine * sin(parameter)
        let horizontalLength = hypot(radial.x, radial.y)
        let longitudeDirection: Vector3D
        if horizontalLength <= 1.0e-12,
           let approachDirection = poleApproachDirection(
               parameter: parameter,
               startParameter: startParameter,
               endParameter: endParameter
           ) {
            let derivative = cosine * -sin(parameter) + sine * cos(parameter)
            longitudeDirection = derivative * approachDirection
        } else {
            longitudeDirection = radial
        }
        var longitude = atan2(-longitudeDirection.x, longitudeDirection.y)
        if longitude < 0.0 { longitude += 2.0 * Double.pi }
        return SurfaceParameter(
            u: longitude,
            v: asin(min(max(radial.z, -1.0), 1.0))
        )
    }

    private func poleApproachDirection(
        parameter: Double,
        startParameter: Double,
        endParameter: Double
    ) -> Double? {
        let scale = max(abs(parameter), abs(startParameter), abs(endParameter), 1.0)
        let endpointTolerance = Double.ulpOfOne * scale * 64.0
        let direction = endParameter > startParameter ? 1.0 : -1.0
        if abs(parameter - startParameter) <= endpointTolerance {
            return direction
        }
        if abs(parameter - endParameter) <= endpointTolerance {
            return -direction
        }
        return nil
    }

    private func parameterDistance(from start: SurfaceParameter, to end: SurfaceParameter) -> Double {
        hypot(end.u - start.u, end.v - start.v)
    }

    private func affineParameter(
        origin: Point2D,
        direction: Point2D,
        parameter: Double
    ) -> SurfaceParameter {
        SurfaceParameter(
            u: origin.x + direction.x * parameter,
            v: origin.y + direction.y * parameter
        )
    }

    private func normalizedFraction(
        _ parameter: Double,
        domain: ParameterDomain,
        tolerance: ModelingTolerance
    ) throws -> Double {
        try domain.validate(tolerance: tolerance)
        switch domain {
        case let .closed(lower, upper):
            guard parameter >= lower - tolerance.distance,
                  parameter <= upper + tolerance.distance else {
                throw GeometryError.invalidDistance(parameter)
            }
            return (parameter - lower) / (upper - lower)
        case let .periodic(period):
            let remainder = parameter.truncatingRemainder(dividingBy: period)
            return (remainder >= 0.0 ? remainder : remainder + period) / period
        case .unbounded:
            throw GeometryError.invalidDistance(parameter)
        }
    }

    private func harmonicParameter(
        center: Point2D,
        cosine: Point2D,
        sine: Point2D,
        parameter: Double
    ) -> SurfaceParameter {
        SurfaceParameter(
            u: center.x + cosine.x * cos(parameter) + sine.x * sin(parameter),
            v: center.y + cosine.y * cos(parameter) + sine.y * sin(parameter)
        )
    }

    private func interpolated(_ start: Double, _ end: Double, fraction: Double) -> Double {
        start + (end - start) * fraction
    }
}

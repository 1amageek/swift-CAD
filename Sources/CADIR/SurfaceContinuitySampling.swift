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
    case constantU(u: Double, vStart: Double, vEnd: Double)
    case constantV(v: Double, uStart: Double, uEnd: Double)
    case polyline([SurfaceParameter])
    case bSpline(BSplineCurve2D)

    public static func boundary(
        _ boundary: SurfaceParameterBoundary,
        on surface: Surface3D,
        tolerance: ModelingTolerance = .standard
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
        tolerance: ModelingTolerance = .standard
    ) throws {
        try tolerance.validate()
        switch self {
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
        tolerance: ModelingTolerance = .standard
    ) throws -> SurfaceParameter {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.distance,
              fraction <= 1.0 + tolerance.distance else {
            throw GeometryError.invalidDistance(fraction)
        }
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        switch self {
        case let .constantU(u, vStart, vEnd):
            return SurfaceParameter(u: u, v: interpolated(vStart, vEnd, fraction: clampedFraction))
        case let .constantV(v, uStart, uEnd):
            return SurfaceParameter(u: interpolated(uStart, uEnd, fraction: clampedFraction), v: v)
        case let .polyline(points):
            return try polylineParameter(points: points, fraction: clampedFraction)
        case let .bSpline(curve):
            let bounds = try Self.closedBounds(curve.domain, tolerance: tolerance)
            let parameter = interpolated(bounds.lower, bounds.upper, fraction: clampedFraction)
            let point = try curve.point(at: parameter, tolerance: tolerance)
            return SurfaceParameter(u: point.x, v: point.y)
        }
    }

    public func startParameter(tolerance: ModelingTolerance = .standard) throws -> SurfaceParameter {
        try parameter(atNormalizedFraction: 0.0, tolerance: tolerance)
    }

    public func endParameter(tolerance: ModelingTolerance = .standard) throws -> SurfaceParameter {
        try parameter(atNormalizedFraction: 1.0, tolerance: tolerance)
    }

    public func reversed(tolerance: ModelingTolerance = .standard) throws -> SurfaceParameterCurve {
        try tolerance.validate()
        switch self {
        case let .constantU(u, vStart, vEnd):
            return .constantU(u: u, vStart: vEnd, vEnd: vStart)
        case let .constantV(v, uStart, uEnd):
            return .constantV(v: v, uStart: uEnd, uEnd: uStart)
        case let .polyline(points):
            return .polyline(Array(points.reversed()))
        case let .bSpline(curve):
            return .bSpline(try curve.reversed(tolerance: tolerance))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case u
        case v
        case uStart
        case uEnd
        case vStart
        case vEnd
        case points
        case bSpline
    }

    private enum Kind: String, Codable {
        case constantU
        case constantV
        case polyline
        case bSpline
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
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
        case .polyline:
            try container.validateOnlyExpectedKeys([.kind, .points], in: decoder)
            self = .polyline(try container.decode([SurfaceParameter].self, forKey: .points))
        case .bSpline:
            try container.validateOnlyExpectedKeys([.kind, .bSpline], in: decoder)
            self = .bSpline(try container.decode(BSplineCurve2D.self, forKey: .bSpline))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
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
        case let .polyline(points):
            try container.encode(Kind.polyline, forKey: .kind)
            try container.encode(points, forKey: .points)
        case let .bSpline(curve):
            try container.encode(Kind.bSpline, forKey: .kind)
            try container.encode(curve, forKey: .bSpline)
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

    private func parameterDistance(from start: SurfaceParameter, to end: SurfaceParameter) -> Double {
        hypot(end.u - start.u, end.v - start.v)
    }

    private func interpolated(_ start: Double, _ end: Double, fraction: Double) -> Double {
        start + (end - start) * fraction
    }
}

public struct SurfaceContinuitySamplingSide: Codable, Sendable, Hashable {
    public var surface: Surface3D
    public var parameterCurve: SurfaceParameterCurve
    public var parameterDirection: SurfaceParameterCurveDirection
    public var frameOrientation: SurfaceFrameOrientation

    public init(
        surface: Surface3D,
        parameterCurve: SurfaceParameterCurve,
        parameterDirection: SurfaceParameterCurveDirection = .forward,
        frameOrientation: SurfaceFrameOrientation = .forward
    ) {
        self.surface = surface
        self.parameterCurve = parameterCurve
        self.parameterDirection = parameterDirection
        self.frameOrientation = frameOrientation
    }

    public func target(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance = .standard
    ) throws -> SurfaceContinuityTarget {
        let directedFraction: Double
        switch parameterDirection {
        case .forward:
            directedFraction = fraction
        case .reversed:
            directedFraction = 1.0 - fraction
        }
        let parameter = try parameterCurve.parameter(
            atNormalizedFraction: directedFraction,
            tolerance: tolerance
        )
        return SurfaceContinuityTarget(
            surface: surface,
            u: parameter.u,
            v: parameter.v,
            orientation: frameOrientation
        )
    }
}

public struct SurfaceContinuitySamplingOptions: Codable, Sendable, Hashable {
    public var sampleCount: Int

    public init(sampleCount: Int = 5) {
        self.sampleCount = sampleCount
    }

    public func validate() throws {
        guard sampleCount >= 2 else {
            throw GeometryError.invalidDistance(Double(sampleCount))
        }
    }
}

public struct SurfaceContinuitySampler: Sendable {
    private let modelingTolerance: ModelingTolerance

    public init(modelingTolerance: ModelingTolerance = .standard) {
        self.modelingTolerance = modelingTolerance
    }

    public func request(
        first: SurfaceContinuitySamplingSide,
        second: SurfaceContinuitySamplingSide,
        requiredLevel: SurfaceContinuityLevel,
        tolerances: SurfaceContinuityTolerances = .standard(),
        options: SurfaceContinuitySamplingOptions = SurfaceContinuitySamplingOptions()
    ) throws -> SurfaceContinuityRequest {
        try modelingTolerance.validate()
        try tolerances.validate()
        try options.validate()
        try first.parameterCurve.validate(on: first.surface, tolerance: modelingTolerance)
        try second.parameterCurve.validate(on: second.surface, tolerance: modelingTolerance)
        let samplePairs = try (0..<options.sampleCount).map { index in
            let fraction = Double(index) / Double(options.sampleCount - 1)
            return SurfaceContinuitySamplePair(
                first: try first.target(atNormalizedFraction: fraction, tolerance: modelingTolerance),
                second: try second.target(atNormalizedFraction: fraction, tolerance: modelingTolerance)
            )
        }
        return SurfaceContinuityRequest(
            samplePairs: samplePairs,
            requiredLevel: requiredLevel,
            tolerances: tolerances
        )
    }
}

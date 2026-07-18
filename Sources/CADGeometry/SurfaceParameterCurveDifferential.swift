import CADCore
import Foundation

public struct SurfaceParameterCurveDifferential: Sendable, Hashable {
    public var parameter: SurfaceParameter
    public var firstDerivative: Point2D

    public init(parameter: SurfaceParameter, firstDerivative: Point2D) {
        self.parameter = parameter
        self.firstDerivative = firstDerivative
    }
}

public extension SurfaceParameterCurve {
    func differentialGeometry(
        atNormalizedFraction fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveDifferential {
        try tolerance.validate()
        guard fraction.isFinite,
              fraction >= -tolerance.distance,
              fraction <= 1.0 + tolerance.distance else {
            throw GeometryError.invalidDistance(fraction)
        }
        let clampedFraction = min(max(fraction, 0.0), 1.0)
        switch self {
        case let .affine(origin, direction, startParameter, endParameter):
            let span = endParameter - startParameter
            let curveParameter = startParameter + span * clampedFraction
            return SurfaceParameterCurveDifferential(
                parameter: SurfaceParameter(
                    u: origin.x + direction.x * curveParameter,
                    v: origin.y + direction.y * curveParameter
                ),
                firstDerivative: Point2D(
                    x: direction.x * span,
                    y: direction.y * span
                )
            )
        case let .constantU(u, vStart, vEnd):
            let span = vEnd - vStart
            return SurfaceParameterCurveDifferential(
                parameter: SurfaceParameter(
                    u: u,
                    v: vStart + span * clampedFraction
                ),
                firstDerivative: Point2D(x: 0.0, y: span)
            )
        case let .constantV(v, uStart, uEnd):
            let span = uEnd - uStart
            return SurfaceParameterCurveDifferential(
                parameter: SurfaceParameter(
                    u: uStart + span * clampedFraction,
                    v: v
                ),
                firstDerivative: Point2D(x: span, y: 0.0)
            )
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            let span = endParameter - startParameter
            let curveParameter = startParameter + span * clampedFraction
            let cosineValue = cos(curveParameter)
            let sineValue = sin(curveParameter)
            return SurfaceParameterCurveDifferential(
                parameter: SurfaceParameter(
                    u: center.x + cosine.x * cosineValue + sine.x * sineValue,
                    v: center.y + cosine.y * cosineValue + sine.y * sineValue
                ),
                firstDerivative: Point2D(
                    x: (-cosine.x * sineValue + sine.x * cosineValue) * span,
                    y: (-cosine.y * sineValue + sine.y * cosineValue) * span
                )
            )
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            let span = endParameter - startParameter
            let curveParameter = startParameter + span * clampedFraction
            let radial = cosine * cos(curveParameter) + sine * sin(curveParameter)
            let radialDerivative = (
                cosine * -sin(curveParameter) + sine * cos(curveParameter)
            ) * span
            let longitudeDenominator = radial.x * radial.x + radial.y * radial.y
            let latitudeDenominator = sqrt(max(0.0, 1.0 - radial.z * radial.z))
            guard longitudeDenominator > tolerance.angle * tolerance.angle,
                  latitudeDenominator > tolerance.angle else {
                throw KernelError(
                    phase: .geometry,
                    code: .singularSystem,
                    tolerance: tolerance,
                    message: "A spherical pcurve differential is singular at a parameter pole."
                )
            }
            var longitude = atan2(-radial.x, radial.y)
            if longitude < 0.0 {
                longitude += 2.0 * Double.pi
            }
            return SurfaceParameterCurveDifferential(
                parameter: SurfaceParameter(
                    u: longitude,
                    v: asin(min(max(radial.z, -1.0), 1.0))
                ),
                firstDerivative: Point2D(
                    x: (
                        -radial.y * radialDerivative.x
                            + radial.x * radialDerivative.y
                    ) / longitudeDenominator,
                    y: radialDerivative.z / latitudeDenominator
                )
            )
        case let .polyline(points):
            return try polylineDifferential(
                points: points,
                fraction: clampedFraction,
                tolerance: tolerance
            )
        case let .bSpline(curve):
            guard case let .closed(lower, upper) = curve.domain else {
                throw GeometryError.invalidDistance(0.0)
            }
            let span = upper - lower
            let curveParameter = lower + span * clampedFraction
            let geometry = try curve.differentialGeometry(
                at: curveParameter,
                tolerance: tolerance
            )
            return SurfaceParameterCurveDifferential(
                parameter: SurfaceParameter(
                    u: geometry.position.x,
                    v: geometry.position.y
                ),
                firstDerivative: Point2D(
                    x: geometry.firstDerivative.x * span,
                    y: geometry.firstDerivative.y * span
                )
            )
        }
    }

    private func polylineDifferential(
        points: [SurfaceParameter],
        fraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurveDifferential {
        guard points.count >= 2 else {
            throw GeometryError.invalidDistance(Double(points.count))
        }
        var segments: [(
            start: SurfaceParameter,
            end: SurfaceParameter,
            length: Double
        )] = []
        var totalLength = 0.0
        for index in 1..<points.count {
            let start = points[index - 1]
            let end = points[index]
            let length = hypot(end.u - start.u, end.v - start.v)
            if length > Double.ulpOfOne {
                segments.append((start: start, end: end, length: length))
                totalLength += length
            }
        }
        guard totalLength > Double.ulpOfOne else {
            throw GeometryError.invalidDistance(totalLength)
        }
        let targetLength = totalLength * fraction
        var accumulatedLength = 0.0
        for (index, segment) in segments.enumerated() {
            let upperLength = accumulatedLength + segment.length
            if targetLength <= upperLength || index == segments.count - 1 {
                let localFraction = min(max(
                    (targetLength - accumulatedLength) / segment.length,
                    0.0
                ), 1.0)
                let uDelta = segment.end.u - segment.start.u
                let vDelta = segment.end.v - segment.start.v
                return SurfaceParameterCurveDifferential(
                    parameter: SurfaceParameter(
                        u: segment.start.u + uDelta * localFraction,
                        v: segment.start.v + vDelta * localFraction
                    ),
                    firstDerivative: Point2D(
                        x: uDelta * totalLength / segment.length,
                        y: vDelta * totalLength / segment.length
                    )
                )
            }
            accumulatedLength = upperLength
        }
        throw KernelError(
            phase: .geometry,
            code: .intersectionFailure,
            tolerance: tolerance,
            message: "Polyline pcurve differential evaluation did not locate a parameter segment."
        )
    }
}

import Foundation
import CADCore

public extension SurfaceParameterCurve {
    func subcurve(
        fromNormalizedFraction startFraction: Double,
        toNormalizedFraction endFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameterCurve {
        try tolerance.validate()
        guard startFraction.isFinite,
              endFraction.isFinite,
              startFraction >= -tolerance.relative,
              endFraction <= 1.0 + tolerance.relative,
              endFraction - startFraction > tolerance.relative else {
            throw GeometryError.invalidDistance(endFraction - startFraction)
        }
        let lowerFraction = min(max(startFraction, 0.0), 1.0)
        let upperFraction = min(max(endFraction, 0.0), 1.0)
        if lowerFraction == 0.0, upperFraction == 1.0 {
            return self
        }
        switch self {
        case let .affine(origin, direction, startParameter, endParameter):
            return .affine(
                origin: origin,
                direction: direction,
                startParameter: interpolated(
                    startParameter,
                    endParameter,
                    fraction: lowerFraction
                ),
                endParameter: interpolated(
                    startParameter,
                    endParameter,
                    fraction: upperFraction
                )
            )
        case let .constantU(u, vStart, vEnd):
            return .constantU(
                u: u,
                vStart: interpolated(vStart, vEnd, fraction: lowerFraction),
                vEnd: interpolated(vStart, vEnd, fraction: upperFraction)
            )
        case let .constantV(v, uStart, uEnd):
            return .constantV(
                v: v,
                uStart: interpolated(uStart, uEnd, fraction: lowerFraction),
                uEnd: interpolated(uStart, uEnd, fraction: upperFraction)
            )
        case let .harmonic(center, cosine, sine, startParameter, endParameter):
            return .harmonic(
                center: center,
                cosine: cosine,
                sine: sine,
                startParameter: interpolated(
                    startParameter,
                    endParameter,
                    fraction: lowerFraction
                ),
                endParameter: interpolated(
                    startParameter,
                    endParameter,
                    fraction: upperFraction
                )
            )
        case let .sphericalGreatCircle(cosine, sine, startParameter, endParameter):
            return .sphericalGreatCircle(
                cosine: cosine,
                sine: sine,
                startParameter: interpolated(
                    startParameter,
                    endParameter,
                    fraction: lowerFraction
                ),
                endParameter: interpolated(
                    startParameter,
                    endParameter,
                    fraction: upperFraction
                )
            )
        case let .polyline(points):
            return .polyline(try polylineSubcurve(
                points,
                lowerFraction: lowerFraction,
                upperFraction: upperFraction,
                tolerance: tolerance
            ))
        case let .bSpline(curve):
            guard case let .closed(lower, upper) = curve.domain else {
                throw KernelError(
                    phase: .geometry,
                    code: .invalidInput,
                    tolerance: tolerance,
                    message: "A B-spline pcurve must have a bounded parameter domain before subdivision."
                )
            }
            return .bSpline(try curve.trimmed(
                from: interpolated(lower, upper, fraction: lowerFraction),
                to: interpolated(lower, upper, fraction: upperFraction),
                tolerance: tolerance
            ))
        case let .certifiedImplicit(curve):
            return .certifiedImplicit(try curve.subcurve(
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                tolerance: tolerance
            ))
        case let .certifiedAnalyticImplicit(curve):
            return .certifiedAnalyticImplicit(try curve.subcurve(
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                tolerance: tolerance
            ))
        case let .certifiedAnalyticPair(curve):
            return .certifiedAnalyticPair(try curve.subcurve(
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                tolerance: tolerance
            ))
        case let .projectedAnalytic(curve):
            return .projectedAnalytic(try curve.subcurve(
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                tolerance: tolerance
            ))
        case let .rigidImage(curve):
            return .rigidImage(try curve.subcurve(
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                tolerance: tolerance
            ))
        case let .offsetSurfaceImage(curve):
            return .offsetSurfaceImage(try curve.subcurve(
                fromNormalizedFraction: lowerFraction,
                toNormalizedFraction: upperFraction,
                tolerance: tolerance
            ))
        case let .periodicTranslation(base, uShift, vShift):
            return .periodicTranslation(
                base: try base.subcurve(
                    fromNormalizedFraction: lowerFraction,
                    toNormalizedFraction: upperFraction,
                    tolerance: tolerance
                ),
                uShift: uShift,
                vShift: vShift
            )
        }
    }

    private func polylineSubcurve(
        _ points: [SurfaceParameter],
        lowerFraction: Double,
        upperFraction: Double,
        tolerance: ModelingTolerance
    ) throws -> [SurfaceParameter] {
        guard points.count >= 2 else {
            throw GeometryError.invalidDistance(Double(points.count))
        }
        var cumulativeLengths = [0.0]
        for index in 1..<points.count {
            cumulativeLengths.append(
                cumulativeLengths[index - 1]
                    + hypot(
                        points[index].u - points[index - 1].u,
                        points[index].v - points[index - 1].v
                    )
            )
        }
        guard let totalLength = cumulativeLengths.last,
              totalLength > tolerance.distance else {
            throw GeometryError.invalidDistance(cumulativeLengths.last ?? 0.0)
        }
        let lowerLength = totalLength * lowerFraction
        let upperLength = totalLength * upperFraction
        var result = [try polylinePoint(
            points,
            cumulativeLengths: cumulativeLengths,
            distance: lowerLength,
            tolerance: tolerance
        )]
        for index in 1..<(points.count - 1) where
            cumulativeLengths[index] > lowerLength + tolerance.distance
                && cumulativeLengths[index] < upperLength - tolerance.distance {
            result.append(points[index])
        }
        result.append(try polylinePoint(
            points,
            cumulativeLengths: cumulativeLengths,
            distance: upperLength,
            tolerance: tolerance
        ))
        guard hypot(
            result[0].u - result[result.count - 1].u,
            result[0].v - result[result.count - 1].v
        ) > tolerance.distance else {
            throw GeometryError.invalidDistance(upperLength - lowerLength)
        }
        return result
    }

    private func polylinePoint(
        _ points: [SurfaceParameter],
        cumulativeLengths: [Double],
        distance: Double,
        tolerance: ModelingTolerance
    ) throws -> SurfaceParameter {
        for index in 1..<points.count where distance <= cumulativeLengths[index] + tolerance.distance {
            let lower = cumulativeLengths[index - 1]
            let upper = cumulativeLengths[index]
            guard upper - lower > tolerance.distance else { continue }
            let fraction = min(max((distance - lower) / (upper - lower), 0.0), 1.0)
            return SurfaceParameter(
                u: interpolated(points[index - 1].u, points[index].u, fraction: fraction),
                v: interpolated(points[index - 1].v, points[index].v, fraction: fraction)
            )
        }
        guard let last = points.last else {
            throw GeometryError.invalidDistance(distance)
        }
        return last
    }

    private func interpolated(
        _ lower: Double,
        _ upper: Double,
        fraction: Double
    ) -> Double {
        lower + (upper - lower) * fraction
    }
}

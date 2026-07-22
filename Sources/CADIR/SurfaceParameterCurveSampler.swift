import CADCore
import CADTopology
import Foundation

public struct SurfaceParameterCurveSampler: Sendable {
    public var tolerance: ModelingTolerance
    public var maximumDepth: Int
    public var maximumSampleCount: Int

    public init(
        tolerance: ModelingTolerance,
        maximumDepth: Int = 20,
        maximumSampleCount: Int = 65_536
    ) {
        self.tolerance = tolerance
        self.maximumDepth = maximumDepth
        self.maximumSampleCount = maximumSampleCount
    }

    public func sample(_ curve: SurfaceParameterCurve) throws -> [SurfaceParameter] {
        try tolerance.validate()
        guard maximumDepth >= 0, maximumSampleCount >= 2 else {
            throw FeatureEvaluationError.invalidGraph(
                "Surface parameter curve sampler limits must permit at least one segment."
            )
        }
        let breakpoints = try samplingBreakpoints(for: curve)
        guard let firstFraction = breakpoints.first else {
            throw FeatureEvaluationError.invalidGraph(
                "Surface parameter curve sampling requires a non-empty parameter domain."
            )
        }
        var lowerFraction = firstFraction
        var lower = try curve.parameter(
            atNormalizedFraction: lowerFraction,
            tolerance: tolerance
        )
        var points = [lower]
        for upperFraction in breakpoints.dropFirst() {
            let upper = try curve.parameter(
                atNormalizedFraction: upperFraction,
                tolerance: tolerance
            )
            try appendSamples(
                curve: curve,
                lowerFraction: lowerFraction,
                lower: lower,
                upperFraction: upperFraction,
                upper: upper,
                depth: 0,
                points: &points
            )
            lowerFraction = upperFraction
            lower = upper
        }
        return points
    }

    private func samplingBreakpoints(
        for curve: SurfaceParameterCurve
    ) throws -> [Double] {
        guard case let .bSpline(spline) = curve else {
            return [0.0, 1.0]
        }
        guard case let .closed(lower, upper) = spline.domain,
              upper > lower else {
            throw FeatureEvaluationError.invalidGraph(
                "B-spline parameter curve sampling requires a closed non-degenerate domain."
            )
        }
        let span = upper - lower
        let numericalTolerance = Double.ulpOfOne
            * max(abs(lower), abs(upper), 1.0)
            * 64.0
        var result = [0.0]
        for knot in spline.knots where knot > lower && knot < upper {
            let fraction = (knot - lower) / span
            if result.last.map({ abs($0 - fraction) > numericalTolerance }) != false {
                result.append(fraction)
            }
        }
        result.append(1.0)
        return result
    }

    private func appendSamples(
        curve: SurfaceParameterCurve,
        lowerFraction: Double,
        lower: SurfaceParameter,
        upperFraction: Double,
        upper: SurfaceParameter,
        depth: Int,
        points: inout [SurfaceParameter]
    ) throws {
        let midpointFraction = (lowerFraction + upperFraction) * 0.5
        let midpoint = try curve.parameter(
            atNormalizedFraction: midpointFraction,
            tolerance: tolerance
        )
        let deviation = distance(
            midpoint,
            toSegmentFrom: lower,
            to: upper
        )
        if deviation <= tolerance.distance {
            try appendIfSeparated(upper, to: &points)
            return
        }
        guard depth < maximumDepth else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: deviation,
                tolerance: tolerance,
                message: "Surface parameter curve exhausted its adaptive sampling depth."
            )
        }
        try appendSamples(
            curve: curve,
            lowerFraction: lowerFraction,
            lower: lower,
            upperFraction: midpointFraction,
            upper: midpoint,
            depth: depth + 1,
            points: &points
        )
        try appendSamples(
            curve: curve,
            lowerFraction: midpointFraction,
            lower: midpoint,
            upperFraction: upperFraction,
            upper: upper,
            depth: depth + 1,
            points: &points
        )
    }

    private func appendIfSeparated(
        _ point: SurfaceParameter,
        to points: inout [SurfaceParameter]
    ) throws {
        guard points.last.map({ distance($0, to: point) <= tolerance.distance }) != true else {
            return
        }
        guard points.count < maximumSampleCount else {
            throw KernelError(
                phase: .topology,
                code: .resourceLimitExceeded,
                residual: Double(points.count),
                tolerance: tolerance,
                message: "Surface parameter curve exhausted its adaptive sample-count budget."
            )
        }
        points.append(point)
    }

    private func distance(
        _ start: SurfaceParameter,
        to end: SurfaceParameter
    ) -> Double {
        hypot(end.u - start.u, end.v - start.v)
    }

    private func distance(
        _ point: SurfaceParameter,
        toSegmentFrom start: SurfaceParameter,
        to end: SurfaceParameter
    ) -> Double {
        let du = end.u - start.u
        let dv = end.v - start.v
        let lengthSquared = du * du + dv * dv
        guard lengthSquared > 0.0 else {
            return distance(point, to: start)
        }
        let projectionFraction = max(
            0.0,
            min(
                1.0,
                ((point.u - start.u) * du + (point.v - start.v) * dv) / lengthSquared
            )
        )
        let projection = SurfaceParameter(
            u: start.u + du * projectionFraction,
            v: start.v + dv * projectionFraction
        )
        return distance(point, to: projection)
    }
}

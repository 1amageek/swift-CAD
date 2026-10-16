import CADCore
import CADGeometry
import CADTopology
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(WASILibc)
import WASILibc
#else
#error("CADIR numeric algorithms require the target C math module.")
#endif

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
        var execution = try OriginalQueryExecution.independentGeometry()
        return try sample(curve, using: &execution)
    }

    public func sample(
        _ curve: SurfaceParameterCurve,
        using execution: inout OriginalQueryExecution
    ) throws -> [SurfaceParameter] {
        try execution.checkpoint()
        try tolerance.validate()
        guard maximumDepth >= 0, maximumSampleCount >= 2 else {
            throw FeatureEvaluationError.invalidGraph(
                "Surface parameter curve sampler limits must permit at least one segment."
            )
        }
        let breakpoints = try samplingBreakpoints(for: curve, using: &execution)
        guard let firstFraction = breakpoints.first else {
            throw FeatureEvaluationError.invalidGraph(
                "Surface parameter curve sampling requires a non-empty parameter domain."
            )
        }
        var lowerFraction = firstFraction
        var lower = try curve.parameter(
            atNormalizedFraction: lowerFraction,
            tolerance: tolerance, using: &execution
        )
        try execution.retainStorage(count: 1, stride: MemoryLayout<SurfaceParameter>.stride)
        var points = [lower]
        var capacity = points.count
        for upperFraction in breakpoints.dropFirst() {
            try execution.consumeWork(1)
            let upper = try curve.parameter(
                atNormalizedFraction: upperFraction,
                tolerance: tolerance, using: &execution
            )
            try appendSamples(
                curve: curve,
                lowerFraction: lowerFraction,
                lower: lower,
                upperFraction: upperFraction,
                upper: upper,
                depth: 0,
                points: &points, capacity: &capacity, using: &execution
            )
            lowerFraction = upperFraction
            lower = upper
        }
        try execution.checkpoint()
        return points
    }

    private func samplingBreakpoints(
        for curve: SurfaceParameterCurve, using execution: inout OriginalQueryExecution
    ) throws -> [Double] {
        guard case let .bSpline(spline) = curve else {
            try execution.retainStorage(count: 2, stride: MemoryLayout<Double>.stride)
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
        try execution.retainStorage(count: 1, stride: MemoryLayout<Double>.stride)
        var result = [0.0]
        var capacity = result.count
        for knot in spline.knots {
            try execution.consumeWork(1)
            guard knot > lower && knot < upper else { continue }
            let fraction = (knot - lower) / span
            if result.last.map({ abs($0 - fraction) > numericalTolerance }) != false {
                try reserveAppend(to: &result, capacity: &capacity, using: &execution)
                result.append(fraction)
            }
        }
        try reserveAppend(to: &result, capacity: &capacity, using: &execution)
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
        points: inout [SurfaceParameter], capacity: inout Int,
        using execution: inout OriginalQueryExecution
    ) throws {
        try execution.admitGeometricDepth(depth)
        try execution.consumeWork(1)
        let midpointFraction = (lowerFraction + upperFraction) * 0.5
        let midpoint = try curve.parameter(
            atNormalizedFraction: midpointFraction,
            tolerance: tolerance, using: &execution
        )
        let deviation = distance(
            midpoint,
            toSegmentFrom: lower,
            to: upper
        )
        if deviation <= tolerance.distance {
            try appendIfSeparated(upper, to: &points, capacity: &capacity, using: &execution)
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
            points: &points, capacity: &capacity, using: &execution
        )
        try appendSamples(
            curve: curve,
            lowerFraction: midpointFraction,
            lower: midpoint,
            upperFraction: upperFraction,
            upper: upper,
            depth: depth + 1,
            points: &points, capacity: &capacity, using: &execution
        )
    }

    private func appendIfSeparated(
        _ point: SurfaceParameter,
        to points: inout [SurfaceParameter], capacity: inout Int,
        using execution: inout OriginalQueryExecution
    ) throws {
        try execution.consumeWork(1)
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
        try reserveAppend(to: &points, capacity: &capacity, using: &execution)
        points.append(point)
    }

    private func reserveAppend<Element>(
        to values: inout [Element], capacity: inout Int,
        using execution: inout OriginalQueryExecution
    ) throws {
        guard values.count == capacity else { return }
        let growth = capacity.multipliedReportingOverflow(by: 2)
        guard !growth.overflow else {
            throw FeatureEvaluationError.invalidGraph("Surface parameter sample capacity overflow.")
        }
        let next = max(1, growth.partialValue)
        try execution.retainStorage(count: next, stride: MemoryLayout<Element>.stride)
        values.reserveCapacity(next)
        capacity = next
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

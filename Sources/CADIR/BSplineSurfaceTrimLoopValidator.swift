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
}

public struct BSplineSurfaceTrimLoopValidator: Sendable {
    public var tolerance: ModelingTolerance
    public var maximumSamplingDepth: Int

    public init(
        tolerance: ModelingTolerance,
        maximumSamplingDepth: Int = 20
    ) {
        self.tolerance = tolerance
        self.maximumSamplingDepth = maximumSamplingDepth
    }

    public func validate(
        _ loops: [BSplineSurfaceTrimLoop],
        on surface: BSplineSurface3D
    ) throws {
        try tolerance.validate()
        try surface.validate(tolerance: tolerance)
        guard maximumSamplingDepth >= 0 else {
            throw FeatureEvaluationError.invalidGraph(
                "B-spline surface trim loop validator maximum sampling depth must not be negative."
            )
        }
        guard loops.isEmpty == false else {
            return
        }
        let outerLoops = loops.filter { $0.role == .outer }
        guard outerLoops.count == 1 else {
            throw FeatureEvaluationError.invalidGraph(
                "B-spline surface trims require exactly one outer trim loop."
            )
        }
        let sampler = SurfaceParameterCurveSampler(
            tolerance: tolerance,
            maximumDepth: maximumSamplingDepth
        )
        let sampledLoops = try loops.map { loop in
            try sampledLoop(loop: loop, surface: surface, sampler: sampler)
        }
        guard let outerLoop = sampledLoops.first(where: { $0.role == .outer }) else {
            throw FeatureEvaluationError.invalidGraph(
                "B-spline surface trims require an outer trim loop."
            )
        }
        try validateSimpleLoop(
            outerLoop.points,
            description: "outer B-spline surface trim loop"
        )
        let innerLoops = sampledLoops.filter { $0.role == .inner }
        for innerLoop in innerLoops {
            try validateSimpleLoop(
                innerLoop.points,
                description: "inner B-spline surface trim loop"
            )
            try validate(
                innerLoop,
                isInside: outerLoop
            )
        }
        for firstIndex in innerLoops.indices {
            for secondIndex in innerLoops.indices where secondIndex > firstIndex {
                try validateDisjoint(
                    innerLoops[firstIndex],
                    innerLoops[secondIndex]
                )
            }
        }
    }

    private struct SampledLoop {
        var role: LoopRole
        var points: [SurfaceParameter]
    }

    private func sampledLoop(
        loop: BSplineSurfaceTrimLoop,
        surface: BSplineSurface3D,
        sampler: SurfaceParameterCurveSampler
    ) throws -> SampledLoop {
        try loop.validate(on: surface, tolerance: tolerance)
        var points: [SurfaceParameter] = []
        for edge in loop.edges {
            let edgePoints = try sampler.sample(edge.parameterCurve)
            guard edgePoints.count >= 2 else {
                throw FeatureEvaluationError.invalidGraph(
                    "B-spline surface trim edge sampling produced fewer than two points."
                )
            }
            if points.last.map({ $0.isApproximatelyEqual(to: edgePoints[0], tolerance: tolerance.distance) }) != true {
                points.append(edgePoints[0])
            }
            for point in edgePoints.dropFirst().dropLast() {
                appendIfSeparated(point, to: &points)
            }
        }
        if let first = points.first,
           let last = points.last,
           first.isApproximatelyEqual(to: last, tolerance: tolerance.distance) {
            points.removeLast()
        }
        return SampledLoop(role: loop.role, points: points)
    }

    private func validateSimpleLoop(
        _ points: [SurfaceParameter],
        description: String
    ) throws {
        guard points.count >= 3 else {
            throw FeatureEvaluationError.invalidGraph(
                "\(description) requires at least three sampled points."
            )
        }
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            let edgeLength = distance(current, to: next)
            guard edgeLength > tolerance.distance else {
                throw FeatureEvaluationError.invalidDistance(edgeLength)
            }
        }
        let area = polygonSignedArea(points)
        guard abs(area) > tolerance.distance * tolerance.distance else {
            throw FeatureEvaluationError.invalidGraph(
                "\(description) has degenerate sampled area."
            )
        }
        for firstIndex in points.indices {
            let firstStart = points[firstIndex]
            let firstEnd = points[(firstIndex + 1) % points.count]
            for secondIndex in points.indices where secondIndex > firstIndex {
                let areAdjacent = (firstIndex + 1) % points.count == secondIndex
                    || (secondIndex + 1) % points.count == firstIndex
                guard areAdjacent == false else {
                    continue
                }
                let secondStart = points[secondIndex]
                let secondEnd = points[(secondIndex + 1) % points.count]
                if segmentsIntersect(
                    firstStart,
                    firstEnd,
                    secondStart,
                    secondEnd
                ) {
                    throw FeatureEvaluationError.invalidGraph(
                        "\(description) must not self-intersect."
                    )
                }
            }
        }
    }

    private func validate(
        _ innerLoop: SampledLoop,
        isInside outerLoop: SampledLoop
    ) throws {
        for point in innerLoop.points {
            guard containsStrictly(point, in: outerLoop.points) else {
                throw FeatureEvaluationError.invalidGraph(
                    "Inner B-spline surface trim loop must lie strictly inside the outer trim loop."
                )
            }
        }
        for innerIndex in innerLoop.points.indices {
            let innerStart = innerLoop.points[innerIndex]
            let innerEnd = innerLoop.points[(innerIndex + 1) % innerLoop.points.count]
            for outerIndex in outerLoop.points.indices {
                let outerStart = outerLoop.points[outerIndex]
                let outerEnd = outerLoop.points[(outerIndex + 1) % outerLoop.points.count]
                guard segmentsIntersect(
                    innerStart,
                    innerEnd,
                    outerStart,
                    outerEnd
                ) == false else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Inner B-spline surface trim loop must not touch or cross the outer trim loop."
                    )
                }
            }
        }
    }

    private func validateDisjoint(
        _ first: SampledLoop,
        _ second: SampledLoop
    ) throws {
        for firstIndex in first.points.indices {
            let firstStart = first.points[firstIndex]
            let firstEnd = first.points[(firstIndex + 1) % first.points.count]
            for secondIndex in second.points.indices {
                let secondStart = second.points[secondIndex]
                let secondEnd = second.points[(secondIndex + 1) % second.points.count]
                guard segmentsIntersect(
                    firstStart,
                    firstEnd,
                    secondStart,
                    secondEnd
                ) == false else {
                    throw FeatureEvaluationError.invalidGraph(
                        "Inner B-spline surface trim loops must not overlap."
                    )
                }
            }
        }
        if let firstPoint = first.points.first,
           containsStrictly(firstPoint, in: second.points) {
            throw FeatureEvaluationError.invalidGraph(
                "Inner B-spline surface trim loops must not be nested."
            )
        }
        if let secondPoint = second.points.first,
           containsStrictly(secondPoint, in: first.points) {
            throw FeatureEvaluationError.invalidGraph(
                "Inner B-spline surface trim loops must not be nested."
            )
        }
    }

    private func containsStrictly(
        _ point: SurfaceParameter,
        in polygon: [SurfaceParameter]
    ) -> Bool {
        guard polygon.count >= 3 else {
            return false
        }
        for index in polygon.indices {
            let start = polygon[index]
            let end = polygon[(index + 1) % polygon.count]
            if distance(point, toSegmentFrom: start, to: end) <= tolerance.distance * 10.0 {
                return false
            }
        }
        var isInside = false
        var previousIndex = polygon.count - 1
        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            let crosses = (current.v > point.v) != (previous.v > point.v)
            if crosses {
                let u = (previous.u - current.u) * (point.v - current.v) /
                    (previous.v - current.v) + current.u
                if point.u < u {
                    isInside.toggle()
                }
            }
            previousIndex = currentIndex
        }
        return isInside
    }

    private func segmentsIntersect(
        _ firstStart: SurfaceParameter,
        _ firstEnd: SurfaceParameter,
        _ secondStart: SurfaceParameter,
        _ secondEnd: SurfaceParameter
    ) -> Bool {
        let areaTolerance = tolerance.distance * tolerance.distance
        let firstSecondStart = cross(firstStart, firstEnd, secondStart)
        let firstSecondEnd = cross(firstStart, firstEnd, secondEnd)
        let secondFirstStart = cross(secondStart, secondEnd, firstStart)
        let secondFirstEnd = cross(secondStart, secondEnd, firstEnd)

        if firstSecondStart > areaTolerance,
           firstSecondEnd < -areaTolerance,
           secondFirstStart < -areaTolerance,
           secondFirstEnd > areaTolerance {
            return true
        }
        if firstSecondStart < -areaTolerance,
           firstSecondEnd > areaTolerance,
           secondFirstStart > areaTolerance,
           secondFirstEnd < -areaTolerance {
            return true
        }
        if abs(firstSecondStart) <= areaTolerance,
           point(secondStart, liesOnSegmentFrom: firstStart, to: firstEnd) {
            return true
        }
        if abs(firstSecondEnd) <= areaTolerance,
           point(secondEnd, liesOnSegmentFrom: firstStart, to: firstEnd) {
            return true
        }
        if abs(secondFirstStart) <= areaTolerance,
           point(firstStart, liesOnSegmentFrom: secondStart, to: secondEnd) {
            return true
        }
        if abs(secondFirstEnd) <= areaTolerance,
           point(firstEnd, liesOnSegmentFrom: secondStart, to: secondEnd) {
            return true
        }
        return false
    }

    private func point(
        _ point: SurfaceParameter,
        liesOnSegmentFrom start: SurfaceParameter,
        to end: SurfaceParameter
    ) -> Bool {
        distance(point, toSegmentFrom: start, to: end) <= tolerance.distance * 10.0
            && point.u >= min(start.u, end.u) - tolerance.distance * 10.0
            && point.u <= max(start.u, end.u) + tolerance.distance * 10.0
            && point.v >= min(start.v, end.v) - tolerance.distance * 10.0
            && point.v <= max(start.v, end.v) + tolerance.distance * 10.0
    }

    private func appendIfSeparated(
        _ point: SurfaceParameter,
        to points: inout [SurfaceParameter]
    ) {
        guard points.last.map({ distance($0, to: point) <= tolerance.distance }) != true else {
            return
        }
        points.append(point)
    }

    private func polygonSignedArea(_ points: [SurfaceParameter]) -> Double {
        var area = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            area += current.u * next.v - next.u * current.v
        }
        return area * 0.5
    }

    private func cross(
        _ first: SurfaceParameter,
        _ second: SurfaceParameter,
        _ third: SurfaceParameter
    ) -> Double {
        (second.u - first.u) * (third.v - first.v)
            - (second.v - first.v) * (third.u - first.u)
    }
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
    let t = max(0.0, min(1.0, ((point.u - start.u) * du + (point.v - start.v) * dv) / lengthSquared))
    let projection = SurfaceParameter(
        u: start.u + du * t,
        v: start.v + dv * t
    )
    return distance(point, to: projection)
}

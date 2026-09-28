import Foundation
import CADCore

public struct SketchCurveSampler: Sendable {
    public var samplesPerSegment: Int
    public var minimumLength: Double

    public init(
        samplesPerSegment: Int = 16,
        minimumLength: Double = 1.0e-12
    ) {
        self.samplesPerSegment = max(samplesPerSegment, 1)
        self.minimumLength = max(minimumLength, 0.0)
    }

    public func lineSamples(
        start: Point2D,
        end: Point2D
    ) -> [CurveEvaluationSample] {
        guard let startSample = lineSample(start: start, end: end, parameter: 0.0),
              let endSample = lineSample(start: start, end: end, parameter: 1.0) else {
            return []
        }
        return [startSample, endSample]
    }

    public func lineSample(
        start: Point2D,
        end: Point2D,
        parameter: Double
    ) -> CurveEvaluationSample? {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = hypot(dx, dy)
        guard length > minimumLength else {
            return nil
        }
        let clampedParameter = clampedUnit(parameter)
        let tangent = Point2D(x: dx / length, y: dy / length)
        return CurveEvaluationSample(
            parameter: clampedParameter,
            point: Point2D(
                x: start.x + dx * clampedParameter,
                y: start.y + dy * clampedParameter
            ),
            tangent: tangent,
            normal: Point2D(x: -tangent.y, y: tangent.x),
            curvature: 0.0
        )
    }

    public func circleSamples(
        center: Point2D,
        radius: Double
    ) -> [CurveEvaluationSample] {
        guard radius > minimumLength else {
            return []
        }
        return circularArcSamples(
            center: center,
            radius: radius,
            startAngle: 0.0,
            span: Double.pi * 2.0,
            count: max(samplesPerSegment * 2, 16)
        )
    }

    public func arcSamples(
        center: Point2D,
        radius: Double,
        startAngle: Double,
        endAngle: Double
    ) -> [CurveEvaluationSample] {
        guard radius > minimumLength else {
            return []
        }
        return circularArcSamples(
            center: center,
            radius: radius,
            startAngle: startAngle,
            span: normalizedAngleSpan(startAngle: startAngle, endAngle: endAngle),
            count: samplesPerSegment
        )
    }

    public func arcSample(
        center: Point2D,
        radius: Double,
        startAngle: Double,
        endAngle: Double,
        parameter: Double
    ) -> CurveEvaluationSample? {
        guard radius > minimumLength else {
            return nil
        }
        let span = normalizedAngleSpan(startAngle: startAngle, endAngle: endAngle)
        return circularArcSample(
            center: center,
            radius: radius,
            startAngle: startAngle,
            span: span,
            parameter: clampedUnit(parameter)
        )
    }

    public func splineSamples(for controlPoints: [Point2D]) -> [CurveEvaluationSample] {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            return []
        }
        let segmentCount = (controlPoints.count - 1) / 3
        var samples: [CurveEvaluationSample] = []
        samples.reserveCapacity(segmentCount * samplesPerSegment + 1)

        for segmentIndex in 0 ..< segmentCount {
            for sampleIndex in 0 ... samplesPerSegment {
                if segmentIndex > 0, sampleIndex == 0 {
                    continue
                }
                let t = Double(sampleIndex) / Double(samplesPerSegment)
                guard let sample = splineSegmentSample(
                    for: controlPoints,
                    segmentIndex: segmentIndex,
                    t: t
                ) else {
                    continue
                }
                samples.append(sample)
            }
        }
        return samples
    }

    public func splineSample(
        for controlPoints: [Point2D],
        parameter: Double
    ) -> CurveEvaluationSample? {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            return nil
        }
        let segmentCount = (controlPoints.count - 1) / 3
        let clampedParameter = clampedUnit(parameter)
        let scaled = clampedParameter * Double(segmentCount)
        let segmentIndex = min(Int(floor(scaled)), segmentCount - 1)
        let localParameter = segmentIndex == segmentCount - 1 && clampedParameter >= 1.0
            ? 1.0
            : scaled - Double(segmentIndex)
        return splineSegmentSample(
            for: controlPoints,
            segmentIndex: segmentIndex,
            t: localParameter
        )
    }

    public func splineSegmentSample(
        for controlPoints: [Point2D],
        segmentIndex: Int,
        t: Double
    ) -> CurveEvaluationSample? {
        guard controlPoints.count >= 4,
              (controlPoints.count - 1).isMultiple(of: 3) else {
            return nil
        }
        let segmentCount = (controlPoints.count - 1) / 3
        guard segmentIndex >= 0, segmentIndex < segmentCount else {
            return nil
        }
        let segmentStart = segmentIndex * 3
        let p0 = controlPoints[segmentStart]
        let p1 = controlPoints[segmentStart + 1]
        let p2 = controlPoints[segmentStart + 2]
        let p3 = controlPoints[segmentStart + 3]
        let clampedParameter = clampedUnit(t)
        return cubicBezierSample(
            p0,
            p1,
            p2,
            p3,
            t: clampedParameter,
            parameter: (Double(segmentIndex) + clampedParameter) / Double(segmentCount)
        )
    }

    /// Uniform samples of a sketch spline of any degree or knots: `samplesPerSegment` per Bezier
    /// segment, the parameter normalized to [0, 1] over the knot domain as for a cubic chain.
    public func splineSamples(for curve: SketchSplineCurve) -> [CurveEvaluationSample] {
        var samples: [CurveEvaluationSample] = []
        for (index, segment) in curve.segments.enumerated() {
            for step in 0...samplesPerSegment where index == 0 || step > 0 {
                let t = Double(step) / Double(samplesPerSegment)
                if let sample = segmentSample(curve, segment, t: t) { samples.append(sample) }
            }
        }
        return samples
    }

    /// The sample of a sketch spline at `parameter`, normalized to [0, 1] over its knot domain.
    public func splineSample(for curve: SketchSplineCurve, parameter: Double) -> CurveEvaluationSample? {
        guard let first = curve.segments.first, let last = curve.segments.last else { return nil }
        let lower = first.lowerParameter, upper = last.upperParameter
        let u = lower + clampedUnit(parameter) * (upper - lower)
        let segment = curve.segments.first { u <= $0.upperParameter } ?? last
        let span = segment.upperParameter - segment.lowerParameter
        return segmentSample(curve, segment, t: span > 0 ? (u - segment.lowerParameter) / span : 0)
    }

    /// Samples dense enough that the tangent turns by at most `maximumTurn` radians between
    /// neighbours: each segment starts from `samplesPerSegment` uniform steps and every step whose
    /// tangents turn further is halved, down to `minimumStep` in the segment parameter. A curvature
    /// comb drawn from them follows tight bends instead of jumping across them.
    public func turnBoundedSplineSamples(
        for curve: SketchSplineCurve,
        maximumTurn: Double = Double.pi / 36,
        minimumStep: Double = 1.0e-6,
        maximumSampleCount: Int = 8_192
    ) throws -> [CurveEvaluationSample] {
        guard maximumTurn.isFinite, maximumTurn > 0, minimumStep > 0 else {
            throw GeometryError.invalidTolerance(distance: minimumStep, angle: maximumTurn)
        }
        var samples: [CurveEvaluationSample] = []
        func refine(_ segment: SketchSplineCurve.Segment, _ a: (t: Double, sample: CurveEvaluationSample?),
                    _ b: (t: Double, sample: CurveEvaluationSample?)) throws {
            if let sa = a.sample, let sb = b.sample,
               turn(sa.tangent, sb.tangent) <= maximumTurn || b.t - a.t <= minimumStep {
                samples.append(sb)
                return
            }
            if a.sample == nil || b.sample == nil, b.t - a.t <= minimumStep {
                if let sb = b.sample { samples.append(sb) }
                return
            }
            guard samples.count < maximumSampleCount else {
                throw SketchError.unsupportedProfile("A curvature comb needs more than \(maximumSampleCount) samples.")
            }
            let middle = (a.t + b.t) / 2
            let m = (middle, segmentSample(curve, segment, t: middle))
            try refine(segment, a, m)
            try refine(segment, m, b)
        }
        for (index, segment) in curve.segments.enumerated() {
            var previous = (t: 0.0, sample: segmentSample(curve, segment, t: 0))
            if index == 0, let first = previous.sample { samples.append(first) }
            for step in 1...samplesPerSegment {
                let t = Double(step) / Double(samplesPerSegment)
                let next = (t: t, sample: segmentSample(curve, segment, t: t))
                try refine(segment, previous, next)
                previous = next
            }
        }
        return samples
    }

    private func turn(_ a: Point2D, _ b: Point2D) -> Double {
        abs(atan2(a.x * b.y - a.y * b.x, a.x * b.x + a.y * b.y))
    }

    /// The sample at `t` in [0, 1] on `segment`, its parameter normalized over the knot domain.
    /// Its derivatives are taken on the B-spline parameter, so curvature does not depend on the
    /// segment's parameter length.
    private func segmentSample(
        _ curve: SketchSplineCurve,
        _ segment: SketchSplineCurve.Segment,
        t: Double
    ) -> CurveEvaluationSample? {
        let p = segment.controlPoints
        let n = Double(p.count - 1)
        var levels = [p]
        while let last = levels.last, last.count > 1 {
            levels.append(zip(last, last.dropFirst()).map {
                Point2D(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t)
            })
        }
        let point = levels[levels.count - 1][0]
        let span = segment.upperParameter - segment.lowerParameter
        guard span > 0, levels.count >= 2 else { return nil }
        let b = levels[levels.count - 2]
        let first = Point2D(x: n * (b[1].x - b[0].x) / span, y: n * (b[1].y - b[0].y) / span)
        var second = Point2D(x: 0, y: 0)
        if levels.count >= 3 {
            let c = levels[levels.count - 3]
            let scale = n * (n - 1) / (span * span)
            second = Point2D(x: scale * (c[2].x - 2 * c[1].x + c[0].x), y: scale * (c[2].y - 2 * c[1].y + c[0].y))
        }
        let speedSquared = first.x * first.x + first.y * first.y
        guard speedSquared > minimumLength * minimumLength else { return nil }
        let speed = speedSquared.squareRoot()
        let tangent = Point2D(x: first.x / speed, y: first.y / speed)
        let curvature = (first.x * second.y - first.y * second.x) / (speedSquared * speed)
        guard curvature.isFinite, let domainFirst = curve.segments.first, let domainLast = curve.segments.last else { return nil }
        let lower = domainFirst.lowerParameter, upper = domainLast.upperParameter
        let u = segment.lowerParameter + t * span
        return CurveEvaluationSample(
            parameter: (u - lower) / (upper - lower),
            point: point,
            tangent: tangent,
            normal: Point2D(x: -tangent.y, y: tangent.x),
            curvature: curvature
        )
    }

    public func approximateLength(of samples: [CurveEvaluationSample]) -> Double {
        guard samples.count >= 2 else {
            return 0.0
        }
        var length = 0.0
        for index in 1 ..< samples.count {
            let previous = samples[index - 1].point
            let current = samples[index].point
            length += hypot(current.x - previous.x, current.y - previous.y)
        }
        return length
    }

    private func circularArcSamples(
        center: Point2D,
        radius: Double,
        startAngle: Double,
        span: Double,
        count: Int
    ) -> [CurveEvaluationSample] {
        let sampleCount = max(count, 1)
        return (0 ... sampleCount).map { index in
            let parameter = Double(index) / Double(sampleCount)
            return circularArcSample(
                center: center,
                radius: radius,
                startAngle: startAngle,
                span: span,
                parameter: parameter
            )
        }
    }

    private func circularArcSample(
        center: Point2D,
        radius: Double,
        startAngle: Double,
        span: Double,
        parameter: Double
    ) -> CurveEvaluationSample {
        let angle = startAngle + span * parameter
        let cosine = cos(angle)
        let sine = sin(angle)
        let tangentSign = span >= 0.0 ? 1.0 : -1.0
        let tangent = Point2D(
            x: -sine * tangentSign,
            y: cosine * tangentSign
        )
        return CurveEvaluationSample(
            parameter: parameter,
            point: Point2D(
                x: center.x + cosine * radius,
                y: center.y + sine * radius
            ),
            tangent: tangent,
            normal: Point2D(
                x: -cosine * tangentSign,
                y: -sine * tangentSign
            ),
            curvature: tangentSign / radius
        )
    }

    private func cubicBezierSample(
        _ p0: Point2D,
        _ p1: Point2D,
        _ p2: Point2D,
        _ p3: Point2D,
        t: Double,
        parameter: Double
    ) -> CurveEvaluationSample? {
        let inverse = 1.0 - t
        let point = cubicBezierPoint(p0, p1, p2, p3, t: t)
        let firstDerivative = Point2D(
            x: 3.0 * inverse * inverse * (p1.x - p0.x)
                + 6.0 * inverse * t * (p2.x - p1.x)
                + 3.0 * t * t * (p3.x - p2.x),
            y: 3.0 * inverse * inverse * (p1.y - p0.y)
                + 6.0 * inverse * t * (p2.y - p1.y)
                + 3.0 * t * t * (p3.y - p2.y)
        )
        let secondDerivative = Point2D(
            x: 6.0 * inverse * (p2.x - 2.0 * p1.x + p0.x)
                + 6.0 * t * (p3.x - 2.0 * p2.x + p1.x),
            y: 6.0 * inverse * (p2.y - 2.0 * p1.y + p0.y)
                + 6.0 * t * (p3.y - 2.0 * p2.y + p1.y)
        )
        let speedSquared = firstDerivative.x * firstDerivative.x + firstDerivative.y * firstDerivative.y
        guard speedSquared > minimumLength * minimumLength else {
            return nil
        }
        let speed = sqrt(speedSquared)
        let tangent = Point2D(
            x: firstDerivative.x / speed,
            y: firstDerivative.y / speed
        )
        let cross = firstDerivative.x * secondDerivative.y - firstDerivative.y * secondDerivative.x
        let curvature = cross / (speedSquared * speed)
        guard curvature.isFinite else {
            return nil
        }
        return CurveEvaluationSample(
            parameter: parameter,
            point: point,
            tangent: tangent,
            normal: Point2D(x: -tangent.y, y: tangent.x),
            curvature: curvature
        )
    }

    private func cubicBezierPoint(
        _ p0: Point2D,
        _ p1: Point2D,
        _ p2: Point2D,
        _ p3: Point2D,
        t: Double
    ) -> Point2D {
        let inverse = 1.0 - t
        let b0 = inverse * inverse * inverse
        let b1 = 3.0 * inverse * inverse * t
        let b2 = 3.0 * inverse * t * t
        let b3 = t * t * t
        return Point2D(
            x: p0.x * b0 + p1.x * b1 + p2.x * b2 + p3.x * b3,
            y: p0.y * b0 + p1.y * b1 + p2.y * b2 + p3.y * b3
        )
    }

    private func normalizedAngleSpan(startAngle: Double, endAngle: Double) -> Double {
        let fullCircle = Double.pi * 2.0
        let tolerance = 1.0e-12
        var span = endAngle - startAngle
        while span <= tolerance {
            span += fullCircle
        }
        while span > fullCircle + tolerance {
            span -= fullCircle
        }
        return min(span, fullCircle)
    }

    private func clampedUnit(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}

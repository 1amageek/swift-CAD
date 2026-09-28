import Foundation
import CADCore

/// The point of a sketch curve nearest a point of its sketch plane, reported with the curve's
/// natural parameter in the convention `SketchCurveIntersector` uses: the fraction along a line,
/// the polar angle about a circle's or an arc's center in [0, 2π), and the chain parameter in
/// [0, span count] of a cubic Bezier chain.
public struct SketchCurveProjector: Sendable {
    /// The nearest curve point and its natural parameter.
    public struct Projection: Sendable, Hashable {
        public var parameter: Double
        public var point: Point2D
        public var distance: Double
    }

    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// A line projects in closed form, clamped to its ends. A circle's nearest point lies on the
    /// ray from its center through `point`; an arc's does too while that ray crosses the arc, and is
    /// otherwise its nearer end. On a cubic Bezier chain every span starts from the nearest of its
    /// samples and converges by Newton steps on (B(t) − p) · B′(t) = 0 inside the span; the nearest
    /// of the spans' feet and the chain's two ends is reported.
    public func nearest(on curve: SketchCurveGeometry2D, to point: Point2D) throws -> Projection {
        try requireFinite([point])
        switch curve {
        case let .line(start, end):
            try requireFinite([start, end])
            let dx = end.x - start.x, dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared.squareRoot() > tolerance.distance else {
                throw invalid("A sketch line must have a length above the modeling distance.")
            }
            let t = min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
            return projection(t, Point2D(x: start.x + dx * t, y: start.y + dy * t), point)
        case let .circle(center, radius):
            try requireRadius(center, radius)
            let angle = polarAngle(of: point, about: center)
            return projection(angle, on(center, radius, angle), point)
        case let .arc(center, radius, startAngle, endAngle):
            try requireRadius(center, radius)
            let sweep = counterclockwise(from: startAngle, to: endAngle)
            guard sweep > tolerance.angle else {
                throw invalid("A sketch arc must sweep a positive angle.")
            }
            let angle = polarAngle(of: point, about: center)
            if counterclockwise(from: startAngle, to: angle) <= sweep {
                return projection(angle, on(center, radius, angle), point)
            }
            let ends = [startAngle, endAngle].map { end -> Projection in
                let normalized = polarAngle(of: on(center, radius, end), about: center)
                return projection(normalized, on(center, radius, end), point)
            }
            return ends[0].distance <= ends[1].distance ? ends[0] : ends[1]
        case let .cubicBezierChain(controlPoints):
            try requireFinite(controlPoints)
            guard controlPoints.count >= 4, (controlPoints.count - 1).isMultiple(of: 3) else {
                throw invalid("A cubic Bezier chain needs 3n + 1 control points.")
            }
            let spanCount = (controlPoints.count - 1) / 3
            var best: Projection?
            for span in 0..<spanCount {
                let p = Array(controlPoints[(span * 3)...(span * 3 + 3)])
                let foot = footPoint(on: p, near: point)
                let candidate = projection(Double(span) + foot.t, foot.point, point)
                if best == nil || candidate.distance < best!.distance { best = candidate }
            }
            guard let best else { throw invalid("A cubic Bezier chain has no span.") }
            return best
        case let .sketchSpline(spline):
            var best: Projection?
            for segment in spline.segments {
                try requireFinite(segment.controlPoints)
                let foot = footPoint(on: segment.controlPoints, near: point)
                let parameter = segment.lowerParameter + foot.t * (segment.upperParameter - segment.lowerParameter)
                let candidate = projection(parameter, foot.point, point)
                if best == nil || candidate.distance < best!.distance { best = candidate }
            }
            guard let best else { throw invalid("A sketch spline has no segment.") }
            return best
        }
    }

    /// The span parameter in [0, 1] of the span's point nearest `point`: its nearest of 65 samples
    /// refined by clamped Newton steps, or the nearer span end when that is closer.
    private func footPoint(on p: [Point2D], near point: Point2D) -> (t: Double, point: Point2D) {
        let sampleCount = 64
        var t = (0...sampleCount).map { Double($0) / Double(sampleCount) }.min {
            squaredDistance(jet(p, $0).value, point) < squaredDistance(jet(p, $1).value, point)
        } ?? 0
        for _ in 0..<32 {
            let (value, first, second) = jet(p, t)
            let offset = Point2D(x: value.x - point.x, y: value.y - point.y)
            let gradient = offset.x * first.x + offset.y * first.y
            let curvature = first.x * first.x + first.y * first.y + offset.x * second.x + offset.y * second.y
            guard curvature > 0 else { break }
            let next = min(max(t - gradient / curvature, 0), 1)
            let moved = abs(next - t)
            t = next
            if moved <= 1e-15 { break }
        }
        let candidates = [t, 0, 1].map { ($0, jet(p, $0).value) }
        let nearest = candidates.min { squaredDistance($0.1, point) < squaredDistance($1.1, point) }!
        return (nearest.0, nearest.1)
    }

    /// B(t), B′(t) and B″(t) of the Bezier span `p` of any degree; the cubic in closed form.
    private func jet(_ p: [Point2D], _ t: Double) -> (value: Point2D, first: Point2D, second: Point2D) {
        guard p.count == 4 else { return generalJet(p, t) }
        let s = 1 - t
        func sum(_ terms: [(Double, Point2D)]) -> Point2D {
            terms.reduce(Point2D(x: 0, y: 0)) { Point2D(x: $0.x + $1.0 * $1.1.x, y: $0.y + $1.0 * $1.1.y) }
        }
        func difference(_ a: Point2D, _ b: Point2D) -> Point2D { Point2D(x: a.x - b.x, y: a.y - b.y) }
        let d0 = difference(p[1], p[0]), d1 = difference(p[2], p[1]), d2 = difference(p[3], p[2])
        return (
            sum([(s * s * s, p[0]), (3 * s * s * t, p[1]), (3 * s * t * t, p[2]), (t * t * t, p[3])]),
            sum([(3 * s * s, d0), (6 * s * t, d1), (3 * t * t, d2)]),
            sum([(6 * s, difference(d1, d0)), (6 * t, difference(d2, d1))])
        )
    }

    /// de Casteljau for degree n: the last level is B(t); the two points before it give
    /// B′(t) = n·(b1 − b0); the three before that give B″(t) = n(n − 1)·(c2 − 2c1 + c0).
    private func generalJet(_ p: [Point2D], _ t: Double) -> (value: Point2D, first: Point2D, second: Point2D) {
        let n = Double(p.count - 1)
        var levels = [p]
        while let last = levels.last, last.count > 1 {
            levels.append(zip(last, last.dropFirst()).map { Point2D(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) })
        }
        let value = levels[levels.count - 1][0]
        guard levels.count >= 2 else { return (value, Point2D(x: 0, y: 0), Point2D(x: 0, y: 0)) }
        let b = levels[levels.count - 2]
        let first = Point2D(x: n * (b[1].x - b[0].x), y: n * (b[1].y - b[0].y))
        guard levels.count >= 3 else { return (value, first, Point2D(x: 0, y: 0)) }
        let c = levels[levels.count - 3]
        let second = Point2D(
            x: n * (n - 1) * (c[2].x - 2 * c[1].x + c[0].x),
            y: n * (n - 1) * (c[2].y - 2 * c[1].y + c[0].y)
        )
        return (value, first, second)
    }

    private func projection(_ parameter: Double, _ foot: Point2D, _ point: Point2D) -> Projection {
        Projection(parameter: parameter, point: foot, distance: squaredDistance(foot, point).squareRoot())
    }

    private func squaredDistance(_ a: Point2D, _ b: Point2D) -> Double {
        (a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)
    }

    private func on(_ center: Point2D, _ radius: Double, _ angle: Double) -> Point2D {
        Point2D(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    /// The polar angle of `point` about `center`, in [0, 2π); the center itself reads as angle 0.
    private func polarAngle(of point: Point2D, about center: Point2D) -> Double {
        var angle = atan2(point.y - center.y, point.x - center.x)
        if angle < 0 { angle += 2 * .pi }
        return angle >= 2 * .pi ? 0 : angle
    }

    /// The counterclockwise sweep from `start` to `end`, in [0, 2π).
    private func counterclockwise(from start: Double, to end: Double) -> Double {
        let sweep = (end - start).truncatingRemainder(dividingBy: 2 * .pi)
        return sweep < 0 ? sweep + 2 * .pi : sweep
    }

    private func requireFinite(_ points: [Point2D]) throws {
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw invalid("A sketch curve projection needs finite coordinates.")
        }
    }

    private func requireRadius(_ center: Point2D, _ radius: Double) throws {
        try requireFinite([center])
        guard radius.isFinite, radius > tolerance.distance else {
            throw invalid("A sketch circle or arc must have a radius above the modeling distance.")
        }
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

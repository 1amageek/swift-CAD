import Foundation
import CADCore

/// The offset of a cubic Bezier chain, or of a sketch spline of any degree and knots through its
/// Bezier segments, as a cubic Bezier chain.
public struct CubicBezierChainOffset: Sendable {
    public let tolerance: ModelingTolerance

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The chain `controlPoints` offset by `distance` to its left (its tangent turned a quarter
    /// turn counterclockwise; a negative distance offsets to the right), within the modeling
    /// distance of the exact offset.
    ///
    /// Each span's offset O(u) = B(u) + d·N(u) is fitted piecewise by cubic Hermite spans whose
    /// ends take O and its exact derivative O′ = B′ + d·N′; a piece whose eight interior samples
    /// stray from O by more than the modeling distance is halved. A span whose offset folds back
    /// (O′ turning against B′, where d·κ reaches 1), a span with no tangent, and a joint whose two
    /// spans' offsets do not meet (a corner, which needs gap fill) are `invalidInput`.
    public func offset(of controlPoints: [Point2D], distance: Double) throws -> [Point2D] {
        try offset(of: controlPoints, distance: distance, gapFill: nil)
    }

    /// How the offsets of two spans meeting at a corner are joined when they part: a round arc
    /// about the corner at the distance, or their end tangents continued until they meet. Where
    /// the offsets cross instead, both are trimmed at the crossing whatever the gap fill.
    public enum GapFill: Sendable, Hashable {
        case round
        case linear
    }

    /// The offset of the chain with its corners joined by `gapFill`; a nil gap fill refuses a
    /// corner whose offsets part. A closed chain (its last point its first) stays closed, its seam
    /// joined like any joint.
    public func offset(of controlPoints: [Point2D], distance: Double, gapFill: GapFill?) throws -> [Point2D] {
        guard controlPoints.count >= 4, (controlPoints.count - 1).isMultiple(of: 3) else {
            throw invalid("A cubic Bezier chain needs 3n + 1 control points.")
        }
        let spans = stride(from: 0, to: controlPoints.count - 1, by: 3).map { Array(controlPoints[$0...($0 + 3)]) }
        return try offset(spans: spans, distance: distance, gapFill: gapFill)
    }

    /// The offset of `curve` with its corners joined by `gapFill`, span by span over its Bezier
    /// segments of any degree, as `offset(of:distance:gapFill:)` does for a cubic chain; a
    /// spline whose last point is its first stays closed.
    public func offset(of curve: SketchSplineCurve, distance: Double, gapFill: GapFill?) throws -> [Point2D] {
        try offset(spans: curve.segments.map(\.controlPoints), distance: distance, gapFill: gapFill)
    }

    /// The offset of consecutive Bezier spans, each span's last point the next one's first.
    private func offset(spans: [[Point2D]], distance: Double, gapFill: GapFill?) throws -> [Point2D] {
        guard let firstSpan = spans.first, let lastSpan = spans.last,
              spans.allSatisfy({ $0.count >= 2 }) else {
            throw invalid("An offset needs at least one span of two or more control points.")
        }
        guard spans.allSatisfy({ $0.allSatisfy { $0.x.isFinite && $0.y.isFinite } }), distance.isFinite else {
            throw invalid("An offset needs finite control points and a finite distance.")
        }
        let spanCount = spans.count
        let isClosed = spanCount > 1 && length(firstSpan[0], lastSpan[lastSpan.count - 1]) <= tolerance.distance
        // Runs of spans whose offsets meet, each one offset chain; corners[i] is the chain point
        // where run i ends and run i + 1 starts.
        var runs: [[Point2D]] = []
        var corners: [Point2D] = []
        for span in 0..<spanCount {
            let p = spans[span]
            var pieces: [Point2D] = []
            try fit(p, distance, 0, 1, depth: 0, into: &pieces)
            if let last = runs.last?.last, length(last, pieces[0]) <= tolerance.distance {
                runs[runs.count - 1] += pieces.dropFirst()
            } else {
                if !runs.isEmpty { corners.append(p[0]) }
                runs.append(pieces)
            }
        }
        var closesAtSeam = false
        if isClosed, let tail = runs.last?.last, let head = runs.first?.first {
            if length(tail, head) <= tolerance.distance {
                if runs.count > 1 {
                    // A smooth seam: the last run continues into the first.
                    runs[0] = runs.removeLast() + runs[0].dropFirst()
                }
            } else {
                corners.append(firstSpan[0])
                closesAtSeam = true
            }
        }
        let cornerCount = corners.count
        guard cornerCount > 0 else { return runs[0] }
        guard let gapFill else {
            throw invalid("The chain has a corner; its offsets need gap fill to meet.")
        }
        // Each corner joins run i's end to run i + 1's start: where they cross, both end at the
        // crossing; where they part, the gap fill runs between them. Trims apply afterwards, so a
        // closed chain of one run can be trimmed at both of its ends.
        var ends = runs.map { Double(($0.count - 1) / 3) }
        var starts = runs.map { _ in 0.0 }
        var joins: [[Point2D]] = []
        for corner in 0..<cornerCount {
            let next = (corner + 1) % runs.count
            let join: (fill: [Point2D], crossing: (tail: Double, head: Double)?)
            if next == corner {
                // A closed chain of one run meets itself at its seam: its last third is the tail
                // and its first third the head, apart from each other, so the run is not
                // intersected with itself. Both cut on span boundaries, so tail parameters shift.
                let spans = (runs[corner].count - 1) / 3
                guard spans >= 3 else {
                    throw invalid("A closed offset of fewer than three spans cannot be joined at its seam.")
                }
                let third = spans / 3
                let tailStart = spans - third
                let found = try joinCorner(
                    Array(runs[corner][(3 * tailStart)...]), Array(runs[corner][...(3 * third)]),
                    at: corners[corner], distance: distance, gapFill: gapFill
                )
                join = (found.fill, found.crossing.map { (Double(tailStart) + $0.tail, $0.head) })
            } else {
                join = try joinCorner(runs[corner], runs[next], at: corners[corner], distance: distance, gapFill: gapFill)
            }
            if let crossing = join.crossing {
                ends[corner] = crossing.tail
                starts[next] = crossing.head
            }
            joins.append(join.fill)
        }
        for run in runs.indices {
            runs[run] = trimmed(runs[run], from: starts[run], to: ends[run])
        }
        for corner in joins.indices where joins[corner].count == 1 {
            // A crossing join is the point both trimmed runs share.
            joins[corner] = [runs[corner][runs[corner].count - 1]]
        }
        var result = runs[0]
        for corner in 0..<cornerCount where corner + 1 < runs.count {
            result += joins[corner].dropFirst()
            result += runs[corner + 1].dropFirst()
        }
        if closesAtSeam {
            result += joins[cornerCount - 1].dropFirst()
            // The seam's join ends where the first run now starts.
            result[result.count - 1] = result[0]
        }
        return result
    }

    /// Joins `tail`'s end to `head`'s start at a corner: where they cross, the chain parameters
    /// of the crossing on each; otherwise the gap fill from the tail's end to the head's start.
    private func joinCorner(
        _ tail: [Point2D],
        _ head: [Point2D],
        at corner: Point2D,
        distance: Double,
        gapFill: GapFill
    ) throws -> (fill: [Point2D], crossing: (tail: Double, head: Double)?) {
        let crossings: [SketchCurveIntersection2D]
        do {
            crossings = try SketchCurveIntersector(tolerance: tolerance).intersections(
                of: .cubicBezierChain(controlPoints: tail), with: .cubicBezierChain(controlPoints: head)
            )
        } catch let error as KernelError {
            throw invalid("The offsets at a corner could not be intersected: \(error.message)")
        }
        if let crossing = crossings.max(by: { $0.firstParameter < $1.firstParameter }) {
            return ([crossing.point], (crossing.firstParameter, crossing.secondParameter))
        }
        let end = tail[tail.count - 1], start = head[0]
        switch gapFill {
        case .round:
            return (try arc(from: end, to: start, about: corner, radius: abs(distance)), nil)
        case .linear:
            let endTangent = direction(tail[tail.count - 2], end)
            let startTangent = direction(start, head[1])
            let cross = endTangent.x * startTangent.y - endTangent.y * startTangent.x
            guard abs(cross) > tolerance.angle else {
                throw invalid("The offsets at a corner are parallel; their tangents do not meet.")
            }
            // end + along·endTangent = start + back·startTangent: the meeting point lies ahead
            // of the tail's end (along > 0) and behind the head's start (back < 0).
            let delta = Point2D(x: start.x - end.x, y: start.y - end.y)
            let along = (delta.x * startTangent.y - delta.y * startTangent.x) / cross
            let back = (delta.x * endTangent.y - delta.y * endTangent.x) / cross
            guard along > 0, back < 0 else {
                throw invalid("The offsets' tangents at a corner meet behind them.")
            }
            let meet = Point2D(x: end.x + endTangent.x * along, y: end.y + endTangent.y * along)
            return (straight(end, meet) + straight(meet, start).dropFirst(), nil)
        }
    }

    /// The arc about `center` from `start` to `end` the short way, as cubic spans within the
    /// modeling distance of the circle.
    private func arc(from start: Point2D, to end: Point2D, about center: Point2D, radius: Double) throws -> [Point2D] {
        let a0 = atan2(start.y - center.y, start.x - center.x)
        var sweep = atan2(end.y - center.y, end.x - center.x) - a0
        if sweep > .pi { sweep -= 2 * .pi }
        if sweep < -.pi { sweep += 2 * .pi }
        for segments in 1...64 {
            let step = sweep / Double(segments)
            let k = 4.0 / 3.0 * tan(step / 4) * radius
            var points = [start]
            var worst = 0.0
            for segment in 0..<segments {
                let from = a0 + step * Double(segment), to = from + step
                let p0 = points[points.count - 1]
                let p3 = segment == segments - 1 ? end : Point2D(x: center.x + radius * cos(to), y: center.y + radius * sin(to))
                let span = [
                    p0,
                    Point2D(x: p0.x - k * sin(from), y: p0.y + k * cos(from)),
                    Point2D(x: p3.x + k * sin(to), y: p3.y - k * cos(to)),
                    p3,
                ]
                for sample in 1...8 {
                    worst = max(worst, abs(length(evaluate(span, Double(sample) / 9), center) - radius))
                }
                points += span.dropFirst()
            }
            if worst <= tolerance.distance { return points }
        }
        throw invalid("The round gap fill did not fit the modeling distance.")
    }

    private func straight(_ a: Point2D, _ b: Point2D) -> [Point2D] {
        [a, Point2D(x: a.x + (b.x - a.x) / 3, y: a.y + (b.y - a.y) / 3),
         Point2D(x: a.x + 2 * (b.x - a.x) / 3, y: a.y + 2 * (b.y - a.y) / 3), b]
    }

    private func direction(_ a: Point2D, _ b: Point2D) -> Point2D {
        let d = length(a, b)
        return Point2D(x: (b.x - a.x) / d, y: (b.y - a.y) / d)
    }

    /// The part of `chain` between chain parameters `u0` and `u1`.
    private func trimmed(_ chain: [Point2D], from u0: Double, to u1: Double) -> [Point2D] {
        let spans = (chain.count - 1) / 3
        func split(_ p: [Point2D], _ t: Double) -> ([Point2D], [Point2D]) {
            func lerp(_ a: Point2D, _ b: Point2D) -> Point2D { Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
            let a = lerp(p[0], p[1]), b = lerp(p[1], p[2]), c = lerp(p[2], p[3])
            let d = lerp(a, b), e = lerp(b, c), f = lerp(d, e)
            return ([p[0], a, d, f], [f, e, c, p[3]])
        }
        var result: [Point2D] = []
        for span in 0..<spans {
            let lower = max(u0, Double(span)), upper = min(u1, Double(span + 1))
            guard upper > lower + 1e-15 else { continue }
            var piece = Array(chain[(3 * span)...(3 * span + 3)])
            let t0 = lower - Double(span), t1 = upper - Double(span)
            if t1 < 1 { piece = split(piece, t1).0 }
            if t0 > 0 { piece = split(piece, t0 / t1).1 }
            result += result.isEmpty ? piece : Array(piece.dropFirst())
        }
        return result
    }

    private func fit(_ p: [Point2D], _ d: Double, _ a: Double, _ b: Double, depth: Int, into result: inout [Point2D]) throws {
        let (startPoint, startDerivative) = try offsetJet(p, d, a)
        let (endPoint, endDerivative) = try offsetJet(p, d, b)
        let h = (b - a) / 3
        let piece = [
            startPoint,
            Point2D(x: startPoint.x + startDerivative.x * h, y: startPoint.y + startDerivative.y * h),
            Point2D(x: endPoint.x - endDerivative.x * h, y: endPoint.y - endDerivative.y * h),
            endPoint,
        ]
        var worst = 0.0
        for sample in 1...8 {
            let t = Double(sample) / 9
            let exact = try offsetJet(p, d, a + (b - a) * t).point
            worst = max(worst, length(evaluate(piece, t), exact))
        }
        if worst > tolerance.distance {
            guard depth < 24 else { throw invalid("The offset did not converge to the modeling distance.") }
            let middle = (a + b) / 2
            try fit(p, d, a, middle, depth: depth + 1, into: &result)
            try fit(p, d, middle, b, depth: depth + 1, into: &result)
            return
        }
        if result.isEmpty { result.append(piece[0]) }
        result += piece.dropFirst()
    }

    /// O(u) and O′(u) of span `p` offset by `d`.
    private func offsetJet(_ p: [Point2D], _ d: Double, _ u: Double) throws -> (point: Point2D, derivative: Point2D) {
        let (value, first, second) = jet(p, u)
        let speed = (first.x * first.x + first.y * first.y).squareRoot()
        guard speed > tolerance.distance else { throw invalid("A span of the chain has no tangent to offset along.") }
        let tangent = Point2D(x: first.x / speed, y: first.y / speed)
        let along = tangent.x * second.x + tangent.y * second.y
        // T′ = (B″ − T (T·B″)) / |B′|, N = T turned a quarter counterclockwise, N′ likewise.
        let turning = Point2D(x: (second.x - tangent.x * along) / speed, y: (second.y - tangent.y * along) / speed)
        let normal = Point2D(x: -tangent.y, y: tangent.x)
        let normalDerivative = Point2D(x: -turning.y, y: turning.x)
        let derivative = Point2D(x: first.x + d * normalDerivative.x, y: first.y + d * normalDerivative.y)
        guard derivative.x * first.x + derivative.y * first.y > 0 else {
            throw invalid("The offset folds back where the distance reaches the curve's radius of curvature.")
        }
        return (Point2D(x: value.x + d * normal.x, y: value.y + d * normal.y), derivative)
    }

    /// B(t), B′(t) and B″(t) of the Bezier span `p` of any degree, by de Casteljau on the
    /// control points and their first and second differences.
    private func jet(_ p: [Point2D], _ t: Double) -> (Point2D, Point2D, Point2D) {
        guard p.count != 4 else { return cubicJet(p, t) }
        func casteljau(_ q: [Point2D]) -> Point2D {
            var level = q
            while level.count > 1 {
                level = zip(level, level.dropFirst()).map { Point2D(x: $0.x + ($1.x - $0.x) * t, y: $0.y + ($1.y - $0.y) * t) }
            }
            return level[0]
        }
        func differences(_ q: [Point2D], _ scale: Double) -> [Point2D] {
            zip(q, q.dropFirst()).map { Point2D(x: ($1.x - $0.x) * scale, y: ($1.y - $0.y) * scale) }
        }
        let n = Double(p.count - 1)
        let first = differences(p, n)
        let second = first.count >= 2 ? differences(first, n - 1) : [Point2D(x: 0, y: 0)]
        return (casteljau(p), casteljau(first), casteljau(second))
    }

    private func cubicJet(_ p: [Point2D], _ t: Double) -> (Point2D, Point2D, Point2D) {
        let s = 1 - t
        let value = Point2D(
            x: s * s * s * p[0].x + 3 * s * s * t * p[1].x + 3 * s * t * t * p[2].x + t * t * t * p[3].x,
            y: s * s * s * p[0].y + 3 * s * s * t * p[1].y + 3 * s * t * t * p[2].y + t * t * t * p[3].y
        )
        let first = Point2D(
            x: 3 * s * s * (p[1].x - p[0].x) + 6 * s * t * (p[2].x - p[1].x) + 3 * t * t * (p[3].x - p[2].x),
            y: 3 * s * s * (p[1].y - p[0].y) + 6 * s * t * (p[2].y - p[1].y) + 3 * t * t * (p[3].y - p[2].y)
        )
        let second = Point2D(
            x: 6 * s * (p[2].x - 2 * p[1].x + p[0].x) + 6 * t * (p[3].x - 2 * p[2].x + p[1].x),
            y: 6 * s * (p[2].y - 2 * p[1].y + p[0].y) + 6 * t * (p[3].y - 2 * p[2].y + p[1].y)
        )
        return (value, first, second)
    }

    private func evaluate(_ p: [Point2D], _ t: Double) -> Point2D {
        jet(p, t).0
    }

    private func length(_ a: Point2D, _ b: Point2D) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

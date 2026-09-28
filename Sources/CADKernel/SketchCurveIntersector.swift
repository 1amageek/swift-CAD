import CADCore
import CADGeometry
import Foundation

/// Certified intersections of two sketch curves in one sketch plane.
///
/// Every curve is converted to its exact (rational) B-spline, the pair is intersected by the
/// certified two-dimensional curve intersector, and each root is reported once with both
/// curves' natural parameters. A root the intersector cannot certify to the modeling distance,
/// such as an inexact tangency or an overlap, is a typed failure rather than a guessed point.
public struct SketchCurveIntersector: Sendable {
    /// How far the second curve reaches.
    public enum Reach: Sendable, Hashable {
        /// The authored curve only.
        case authored
        /// A line as its unbounded line and an arc as its full circle; a circle is unchanged.
        /// A cubic Bezier chain has no extension and is refused.
        case extended
    }

    private let tolerance: ModelingTolerance
    /// The proof budget of one intersection. Transversal roots of sketch curves certify in a few
    /// hundred cells; an overlap or tangency exhausts the budget and fails instead of stalling
    /// an interactive command.
    private let maximumSubdivisionDepth = 32
    private let maximumSubdivisionCells = 16_384

    public init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    /// The intersections of `first` with `second`, ordered by the first curve's parameter.
    public func intersections(
        of first: SketchCurveGeometry2D,
        with second: SketchCurveGeometry2D,
        secondReach: Reach = .authored
    ) throws -> [SketchCurveIntersection2D] {
        try tolerance.validate()
        let firstCurve = try exactCurve(for: first, reach: .authored, covering: nil)
        let secondCurve = try exactCurve(for: second, reach: secondReach, covering: firstCurve.curve)
        let distance = tolerance.distance
        let roots = try RationalBSplineCurveIntersector2D().intersections(
            first: firstCurve.curve,
            second: secondCurve.curve,
            maximumSubdivisionDepth: maximumSubdivisionDepth,
            maximumSubdivisionCells: maximumSubdivisionCells,
            accepting: { $0.pointEnclosure.maximumWidth <= distance },
            tolerance: tolerance
        )
        var result: [SketchCurveIntersection2D] = []
        for root in roots {
            let (firstParameter, secondParameter) = try refined(root, first: firstCurve, second: secondCurve)
            let point = try firstCurve.curve.point(at: firstParameter, tolerance: tolerance)
            let secondPoint = try secondCurve.curve.point(at: secondParameter, tolerance: tolerance)
            // A full circle's seam can certify one crossing at both ends of its domain.
            guard result.contains(where: { hypot($0.point.x - point.x, $0.point.y - point.y) <= distance }) == false else {
                continue
            }
            result.append(SketchCurveIntersection2D(
                point: point,
                firstParameter: firstCurve.naturalParameter(firstParameter, at: point),
                secondParameter: secondCurve.naturalParameter(secondParameter, at: secondPoint)
            ))
        }
        return result.sorted { $0.firstParameter < $1.firstParameter }
    }

    /// The certified root refined to floating-point precision by Newton steps that stay inside
    /// its certified enclosure, which contains exactly one root. When a step would leave the
    /// enclosure or the curves are tangent there (singular Jacobian), the certified midpoint is
    /// kept: the enclosure, not the refinement, is the correctness contract.
    private func refined(
        _ root: RationalBSplineCurveIntersection2D,
        first: ExactCurve,
        second: ExactCurve
    ) throws -> (Double, Double) {
        let firstRange = root.firstParameterEnclosure
        let secondRange = root.secondParameterEnclosure
        var s = first.clamped(firstRange.midpoint)
        var t = second.clamped(secondRange.midpoint)
        func residual(_ s: Double, _ t: Double) throws -> (x: Double, y: Double, first: Point2D, second: Point2D) {
            let a = try first.curve.differentialGeometry(at: s, tolerance: tolerance)
            let b = try second.curve.differentialGeometry(at: t, tolerance: tolerance)
            return (a.position.x - b.position.x, a.position.y - b.position.y, a.firstDerivative, b.firstDerivative)
        }
        var current = try residual(s, t)
        for _ in 0..<16 {
            let determinant = -current.first.x * current.second.y + current.second.x * current.first.y
            guard determinant.isFinite, abs(determinant) > .ulpOfOne else {
                break
            }
            let ds = (-current.x * -current.second.y - -current.second.x * -current.y) / determinant
            let dt = (current.first.x * -current.y - -current.x * current.first.y) / determinant
            let nextS = s + ds
            let nextT = t + dt
            guard firstRange.contains(nextS), secondRange.contains(nextT),
                  first.clamped(nextS) == nextS, second.clamped(nextT) == nextT else {
                break
            }
            let next = try residual(nextS, nextT)
            guard hypot(next.x, next.y) < hypot(current.x, current.y) else {
                break
            }
            s = nextS
            t = nextT
            current = next
        }
        return (s, t)
    }

    /// A curve's exact B-spline and the map from its B-spline parameter to its natural parameter.
    private struct ExactCurve {
        enum NaturalParameter {
            /// The B-spline parameter is the natural parameter.
            case identity
            /// The natural parameter is the polar angle about the center.
            case polarAngle(center: Point2D)
        }

        var curve: BSplineCurve2D
        var natural: NaturalParameter

        func clamped(_ parameter: Double) -> Double {
            guard case let .closed(lower, upper) = curve.domain else {
                return parameter
            }
            return min(max(parameter, lower), upper)
        }

        func naturalParameter(_ parameter: Double, at point: Point2D) -> Double {
            switch natural {
            case .identity:
                return parameter
            case let .polarAngle(center):
                let fullCircle = Double.pi * 2.0
                var angle = atan2(point.y - center.y, point.x - center.x)
                if angle < 0.0 {
                    angle += fullCircle
                }
                return angle >= fullCircle ? 0.0 : angle
            }
        }
    }

    private func exactCurve(
        for geometry: SketchCurveGeometry2D,
        reach: Reach,
        covering other: BSplineCurve2D?
    ) throws -> ExactCurve {
        switch geometry {
        case let .line(start, end):
            try requireFinite([start, end])
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared.squareRoot() > tolerance.distance else {
                throw invalid("A sketch line must have a length above the modeling distance.")
            }
            var lower = 0.0
            var upper = 1.0
            if reach == .extended, let other {
                // Every point of the other curve lies in its control-point box (positive weights),
                // so a line spanning the box's projection meets it wherever the unbounded line does.
                for point in other.controlPoints {
                    let t = ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
                    lower = min(lower, t)
                    upper = max(upper, t)
                }
                lower -= 1.0
                upper += 1.0
            }
            let curve = BSplineCurve2D(
                degree: 1,
                knots: [lower, lower, upper, upper],
                controlPoints: [
                    Point2D(x: start.x + lower * dx, y: start.y + lower * dy),
                    Point2D(x: start.x + upper * dx, y: start.y + upper * dy),
                ]
            )
            return ExactCurve(curve: try validated(curve), natural: .identity)
        case let .circle(center, radius):
            return try circularCurve(center: center, radius: radius, startAngle: 0.0, sweep: Double.pi * 2.0)
        case let .arc(center, radius, startAngle, endAngle):
            if reach == .extended {
                return try circularCurve(center: center, radius: radius, startAngle: 0.0, sweep: Double.pi * 2.0)
            }
            return try circularCurve(
                center: center,
                radius: radius,
                startAngle: startAngle,
                sweep: try positiveSweep(from: startAngle, to: endAngle)
            )
        case let .cubicBezierChain(controlPoints):
            guard reach == .authored else {
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "A cubic Bezier chain has no extension."
                )
            }
            try requireFinite(controlPoints)
            guard controlPoints.count >= 4, (controlPoints.count - 1).isMultiple(of: 3) else {
                throw invalid("A cubic Bezier chain needs 3n + 1 control points.")
            }
            let spanCount = (controlPoints.count - 1) / 3
            var knots = Array(repeating: 0.0, count: 4)
            for boundary in stride(from: 1, to: spanCount, by: 1) {
                knots.append(contentsOf: Array(repeating: Double(boundary), count: 3))
            }
            knots.append(contentsOf: Array(repeating: Double(spanCount), count: 4))
            let curve = BSplineCurve2D(degree: 3, knots: knots, controlPoints: controlPoints)
            return ExactCurve(curve: try validated(curve), natural: .identity)
        case let .sketchSpline(spline):
            guard reach == .authored else {
                throw KernelError(
                    phase: .geometry,
                    code: .unsupportedCapability,
                    tolerance: tolerance,
                    message: "A sketch spline has no extension."
                )
            }
            return ExactCurve(curve: try validated(spline.bSpline), natural: .identity)
        }
    }

    /// The exact rational quadratic circle arc, in spans of at most a quarter turn.
    private func circularCurve(
        center: Point2D,
        radius: Double,
        startAngle: Double,
        sweep: Double
    ) throws -> ExactCurve {
        try requireFinite([center])
        guard radius.isFinite, radius > tolerance.distance else {
            throw invalid("A sketch circle or arc radius must exceed the modeling distance.")
        }
        guard startAngle.isFinite else {
            throw invalid("A sketch arc angle must be finite.")
        }
        let spanCount = max(1, Int((sweep / (Double.pi * 0.5)).rounded(.up)))
        let spanAngle = sweep / Double(spanCount)
        let middleWeight = cos(spanAngle * 0.5)
        func point(_ angle: Double, scale: Double = 1.0) -> Point2D {
            Point2D(
                x: center.x + radius * scale * cos(angle),
                y: center.y + radius * scale * sin(angle)
            )
        }
        var controlPoints = [point(startAngle)]
        var weights = [1.0]
        var knots = [0.0, 0.0, 0.0]
        for span in 0..<spanCount {
            let lower = startAngle + Double(span) * spanAngle
            controlPoints.append(point(lower + spanAngle * 0.5, scale: 1.0 / middleWeight))
            controlPoints.append(point(lower + spanAngle))
            weights.append(contentsOf: [middleWeight, 1.0])
            let knot = Double(span + 1)
            knots.append(contentsOf: span + 1 == spanCount ? [knot, knot, knot] : [knot, knot])
        }
        let curve = BSplineCurve2D(degree: 2, knots: knots, controlPoints: controlPoints, weights: weights)
        return ExactCurve(curve: try validated(curve), natural: .polarAngle(center: center))
    }

    /// The counterclockwise sweep from the start to the end angle; a zero sweep is degenerate.
    private func positiveSweep(from startAngle: Double, to endAngle: Double) throws -> Double {
        guard startAngle.isFinite, endAngle.isFinite else {
            throw invalid("A sketch arc angle must be finite.")
        }
        // Matches profile extraction: equal angles are degenerate, a whole turn is a full sweep.
        let delta = endAngle - startAngle
        guard abs(delta) > tolerance.angle else {
            throw invalid("A sketch arc must sweep a non-zero angle.")
        }
        var sweep = delta.truncatingRemainder(dividingBy: Double.pi * 2.0)
        if sweep <= tolerance.angle {
            sweep += Double.pi * 2.0
        }
        return sweep
    }

    private func validated(_ curve: BSplineCurve2D) throws -> BSplineCurve2D {
        try curve.validate(tolerance: tolerance)
        return curve
    }

    private func requireFinite(_ points: [Point2D]) throws {
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw invalid("Sketch curve coordinates must be finite.")
        }
    }

    private func invalid(_ message: String) -> KernelError {
        KernelError(phase: .geometry, code: .invalidInput, tolerance: tolerance, message: message)
    }
}

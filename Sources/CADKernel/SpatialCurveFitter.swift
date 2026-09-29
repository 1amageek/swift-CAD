import Foundation
import CADCore
import CADGeometry
import CADIR

/// A spatial path through a curve known only by its points: cubic spans whose ends lie on the
/// curve and whose tangents follow it, halved until every span stays within `deviation` of the
/// curve at its sample parameters. Spans never cross a breakpoint, so a corner of the source
/// stays a corner.
public struct SpatialCurveFitter: Sendable {
    public let deviation: Double
    public let maximumSpanCount: Int
    /// Parameters, per span, at which the fitted span is compared with the curve.
    static let checkFractions: [Double] = [0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]

    public init(deviation: Double, maximumSpanCount: Int = 4_096) throws {
        guard deviation.isFinite, deviation > 0, maximumSpanCount > 0 else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: nil, message: "A fit needs a positive deviation and span budget.")
        }
        self.deviation = deviation
        self.maximumSpanCount = maximumSpanCount
    }

    /// Fits `point` over the increasing `breakpoints`. A closed curve's last point is its first.
    public func fit(
        breakpoints: [Double],
        isClosed: Bool,
        tolerance: ModelingTolerance,
        point: (Double) throws -> Point3D
    ) throws -> FittedSpatialCurve {
        let (spans, maximumDeviation) = try fittedSpans(breakpoints: breakpoints, tolerance: tolerance, point: point)
        var knots: [SpatialPathKnot] = [SpatialPathKnot(position: spans[0].p0, outgoing: spans[0].p1 - spans[0].p0)]
        for (index, span) in spans.enumerated() {
            knots[knots.count - 1].outgoing = span.p1 - span.p0
            knots.append(SpatialPathKnot(
                position: span.p3,
                incoming: span.p2 - span.p3,
                outgoing: index + 1 < spans.count ? spans[index + 1].p1 - spans[index + 1].p0 : .zero
            ))
        }
        if isClosed {
            let last = knots.removeLast()
            knots[0].incoming = last.incoming
        }
        let path = SpatialPathFeature(kind: .bezier, knots: knots, isClosed: isClosed)
        try path.validate(tolerance: tolerance)
        return FittedSpatialCurve(path: path, maximumDeviation: maximumDeviation)
    }

    /// Fits `point` over the increasing `breakpoints` as a clamped cubic B-spline on the same
    /// parameters: its spans are the fit's, joined by knots of multiplicity three, so the curve at
    /// a parameter is the fit of `point` there. An edge carried through a map keeps its own
    /// parameters this way, and with them its correspondence to its faces' trimming curves.
    public func fitBSpline(
        breakpoints: [Double],
        tolerance: ModelingTolerance,
        point: (Double) throws -> Point3D
    ) throws -> (curve: BSplineCurve3D, maximumDeviation: Double) {
        let (spans, maximumDeviation) = try fittedSpans(breakpoints: breakpoints, tolerance: tolerance, point: point)
        var knots = Array(repeating: spans[0].lower, count: 4)
        var points = [spans[0].p0]
        for (index, span) in spans.enumerated() {
            points += [span.p1, span.p2, span.p3]
            knots += Array(repeating: span.upper, count: index + 1 < spans.count ? 3 : 4)
        }
        let curve = BSplineCurve3D(degree: 3, knots: knots, controlPoints: points)
        try curve.validate(tolerance: tolerance)
        return (curve, maximumDeviation)
    }

    /// The Hermite spans of the fit, in order, each with the parameters it covers.
    private func fittedSpans(
        breakpoints: [Double],
        tolerance: ModelingTolerance,
        point: (Double) throws -> Point3D
    ) throws -> (spans: [(lower: Double, upper: Double, p0: Point3D, p1: Point3D, p2: Point3D, p3: Point3D)], maximumDeviation: Double) {
        guard breakpoints.count >= 2,
              breakpoints.allSatisfy(\.isFinite),
              zip(breakpoints, breakpoints.dropFirst()).allSatisfy({ $0 < $1 }) else {
            throw KernelError(phase: .validation, code: .invalidInput, tolerance: tolerance, message: "A fit needs increasing finite breakpoints.")
        }
        var spans: [(lower: Double, upper: Double, p0: Point3D, p1: Point3D, p2: Point3D, p3: Point3D)] = []
        var maximumDeviation = 0.0
        for (lower, upper) in zip(breakpoints, breakpoints.dropFirst()) {
            var pending = [(lower, upper)]
            while let (a, b) = pending.popLast() {
                let span = try hermiteSpan(from: a, to: b, point: point)
                var worst = 0.0
                for fraction in Self.checkFractions {
                    let expected = try point(a + (b - a) * fraction)
                    worst = max(worst, (Self.bezier(span, at: fraction) - expected).length)
                }
                if worst <= deviation {
                    spans.append((a, b, span.p0, span.p1, span.p2, span.p3))
                    maximumDeviation = max(maximumDeviation, worst)
                } else {
                    let middle = a + (b - a) * 0.5
                    guard middle > a, middle < b else {
                        throw KernelError(phase: .geometry, code: .singularGeometry, residual: worst, tolerance: tolerance,
                                          message: "The curve cannot be fitted within the deviation.")
                    }
                    // Right half first on the stack's bottom, so spans come out in order.
                    pending.append((middle, b))
                    pending.append((a, middle))
                }
                guard spans.count + pending.count <= maximumSpanCount else {
                    throw KernelError(phase: .geometry, code: .resourceLimitExceeded, residual: worst, tolerance: tolerance,
                                      message: "The fit needs more spans than its budget.")
                }
            }
        }
        return (spans, maximumDeviation)
    }

    /// The cubic through the curve's points at `a` and `b` with its derivatives there, estimated
    /// inside the span so a corner at either end is not crossed.
    private func hermiteSpan(
        from a: Double, to b: Double, point: (Double) throws -> Point3D
    ) throws -> (p0: Point3D, p1: Point3D, p2: Point3D, p3: Point3D) {
        let width = b - a
        let h = width * 1.0e-3
        let p0 = try point(a), p3 = try point(b)
        // Second-order one-sided differences, taken as offsets from each end.
        let d0 = ((try point(a + h) - p0) * 4.0 - (try point(a + 2 * h) - p0)) * (1 / (2 * h))
        let d1 = ((p3 - (try point(b - h))) * 4.0 - (p3 - (try point(b - 2 * h)))) * (1 / (2 * h))
        return (p0, p0 + d0 * (width / 3), p3 + d1 * (-width / 3), p3)
    }

    static func bezier(_ span: (p0: Point3D, p1: Point3D, p2: Point3D, p3: Point3D), at t: Double) -> Point3D {
        let s = 1 - t
        // Bernstein weights sum to one, so the point is p0 plus weighted offsets from it.
        return span.p0 + (span.p1 - span.p0) * (3 * s * s * t) + (span.p2 - span.p0) * (3 * s * t * t)
            + (span.p3 - span.p0) * (t * t * t)
    }
}

public struct FittedSpatialCurve: Equatable, Sendable {
    public var path: SpatialPathFeature
    /// The largest distance found at the check parameters between a span and the curve.
    public var maximumDeviation: Double
}

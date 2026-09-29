import Foundation
import Testing
@testable import CADKernel
import CADCore
import CADGeometry

/// A refit keeps the original's ends, has the asked number of control points and stays close
/// to the original, closer with more points.
@Suite struct SketchSplineLeastSquaresFitTests {
    private let fitter = SketchSplineLeastSquaresFit(tolerance: .standard)

    @Test func aRefitHasTheAskedPointsKeepsTheEndsAndFollowsTheCurve() throws {
        let quintic = try SketchSplineCurve(
            degree: 5, knots: nil,
            controlPoints: [(0.0, 0.0), (1.0, 2.0), (2.0, -1.0), (3.0, 3.0), (4.0, 1.0), (5.0, 2.0)].map { Point2D(x: $0.0, y: $0.1) },
            tolerance: .standard
        )
        var previous = Double.infinity
        for count in [5, 8, 12, 20] {
            let result = try fitter.fit(quintic, degree: 3, controlPointCount: count)
            #expect(result.curve.degree == 3 && result.curve.controlPoints.count == count)
            #expect(result.curve.controlPoints.first == Point2D(x: 0, y: 0))
            #expect(result.curve.controlPoints.last == Point2D(x: 5, y: 2))
            #expect(result.maximumDeviation < previous)
            #expect(result.maximumDeviationFraction >= 0 && result.maximumDeviationFraction <= 1)
            previous = result.maximumDeviation
        }
        #expect(previous < 1e-3)
    }

    /// A line with a 100 mm spike on knot spans a thousandth of its domain wide.
    private func narrowSpike() throws -> SketchSplineCurve {
        try SketchSplineCurve(
            degree: 1, knots: [0, 0, 0.501, 0.502, 0.503, 1, 1],
            controlPoints: [(0.0, 0.0), (0.5, 0.0), (0.5005, 0.1), (0.501, 0.0), (1.0, 0.0)].map { Point2D(x: $0.0, y: $0.1) },
            tolerance: .standard
        )
    }

    /// The true distance from `point` to `result`'s curve.
    private func distance(from point: Point2D, to result: SketchSplineLeastSquaresFit.Result) throws -> Double {
        let curve = SketchCurveGeometry2D.sketchSpline(try SketchSplineCurve(
            degree: result.curve.degree, knots: result.curve.knots, controlPoints: result.curve.controlPoints, tolerance: .standard
        ))
        let foot = try SketchCurveProjector(tolerance: .standard).nearest(on: curve, to: point).point
        return hypot(foot.x - point.x, foot.y - point.y)
    }

    /// Knot spans far narrower than an even sampling of the domain are still fitted and checked:
    /// the reported deviation is never less than the spike's true distance from the fit, and a
    /// refit within a deviation holds the spike within it.
    @Test func aNarrowKnotSpanIsNeitherFittedBlindNorPassedUnchecked() throws {
        let spike = try narrowSpike()
        let apex = Point2D(x: 0.5005, y: 0.1)
        let coarse = try fitter.fit(spike, degree: 3, controlPointCount: 8)
        #expect(coarse.maximumDeviation >= (try distance(from: apex, to: coarse)) - 1e-9)
        #expect(coarse.maximumDeviation > 0.01)
        let refitted = try fitter.refit(spike, deviation: 0.01, keepsCorners: false)
        #expect(refitted.maximumDeviation <= 0.01)
        for point in [apex, Point2D(x: 0.5, y: 0), Point2D(x: 0.501, y: 0), Point2D(x: 0.50025, y: 0.05)] {
            #expect(try distance(from: point, to: refitted) <= 0.01 + 1e-9)
        }
    }

    @Test func aStraightSplineIsRefittedExactly() throws {
        let line = try SketchSplineCurve(
            degree: 3, knots: nil,
            controlPoints: [(0.0, 0.0), (1.0, 1.0), (2.0, 2.0), (3.0, 3.0)].map { Point2D(x: $0.0, y: $0.1) },
            tolerance: .standard
        )
        let result = try fitter.fit(line, degree: 3, controlPointCount: 7)
        #expect(result.maximumDeviation < 1e-9)
    }

    /// The shape weight trades closeness for an even control polygon: at 1 the plain least-squares
    /// fit, lower weights stray further, and at 0 the control points lie evenly on the chord.
    @Test func theShapeWeightTradesClosenessForEvenness() throws {
        let quintic = try SketchSplineCurve(
            degree: 5, knots: nil,
            controlPoints: [(0.0, 0.0), (1.0, 2.0), (2.0, -1.0), (3.0, 3.0), (4.0, 1.0), (5.0, 2.0)].map { Point2D(x: $0.0, y: $0.1) },
            tolerance: .standard
        )
        let plain = try fitter.fit(quintic, degree: 4, controlPointCount: 9)
        let full = try fitter.fit(quintic, degree: 4, controlPointCount: 9, shapeWeight: 1)
        #expect(zip(plain.curve.controlPoints, full.curve.controlPoints).allSatisfy { hypot($0.x - $1.x, $0.y - $1.y) < 1e-12 })
        var previous = 0.0
        for weight in [1.0, 0.9, 0.5, 0.1] {
            let deviation = try fitter.fit(quintic, degree: 4, controlPointCount: 9, shapeWeight: weight).maximumDeviation
            #expect(deviation >= previous - 1e-12)
            previous = deviation
        }
        let straight = try fitter.fit(quintic, degree: 4, controlPointCount: 9, shapeWeight: 0)
        for (index, point) in straight.curve.controlPoints.enumerated() {
            let t = Double(index) / 8
            #expect(hypot(point.x - 5 * t, point.y - 2 * t) < 1e-9)
        }
        #expect(throws: KernelError.self) { try fitter.fit(quintic, degree: 4, controlPointCount: 9, shapeWeight: 1.5) }
    }

    /// A refit takes the fewest cubic control points that stay within the deviation: one fewer
    /// strays further.
    @Test func aRefitTakesTheFewestPointsWithinTheDeviation() throws {
        let quintic = try SketchSplineCurve(
            degree: 5, knots: nil,
            controlPoints: [(0.0, 0.0), (1.0, 2.0), (2.0, -1.0), (3.0, 3.0), (4.0, 1.0), (5.0, 2.0)].map { Point2D(x: $0.0, y: $0.1) },
            tolerance: .standard
        )
        let result = try fitter.refit(quintic, deviation: 1e-3, keepsCorners: false)
        #expect(result.curve.degree == 3)
        #expect(result.maximumDeviation <= 1e-3)
        let count = result.curve.controlPoints.count
        #expect(count > 4)
        #expect(try fitter.fit(quintic, degree: 3, controlPointCount: count - 1).maximumDeviation > 1e-3)
        #expect(throws: KernelError.self) { try fitter.refit(quintic, deviation: 0, keepsCorners: false) }
    }

    /// Keep Corners cuts a quadratic at its corner knot, refits each side and joins them there
    /// with a knot of multiplicity three, so the corner point is a control point of the result and
    /// stays a corner, its sides turning as the original's within the deviation; a smooth
    /// full-multiplicity knot is no corner.
    @Test func keepCornersKeepsTheCornerOfASplineOfAnotherDegree() throws {
        let corner = Point2D(x: 2, y: 2)
        let quadratic = try SketchSplineCurve(
            degree: 2, knots: [0, 0, 0, 0.5, 0.5, 1, 1, 1],
            controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 1, y: 2), corner, Point2D(x: 3, y: 1), Point2D(x: 4, y: -1)],
            tolerance: .standard
        )
        #expect(try fitter.cornerParameters(of: quadratic) == [0.5])
        let result = try fitter.refit(quadratic, deviation: 1e-4, keepsCorners: true)
        #expect(result.maximumDeviation <= 1e-4)
        let knots = result.curve.knots
        guard let index = result.curve.controlPoints.firstIndex(where: { hypot($0.x - corner.x, $0.y - corner.y) < 1e-12 }) else {
            Issue.record("The corner is not a control point of the refit.")
            return
        }
        #expect(knots[index + 1] == knots[index + 2] && knots[index + 2] == knots[index + 3])
        let before = result.curve.controlPoints[index - 1], after = result.curve.controlPoints[index + 1]
        let incoming = atan2(corner.y - before.y, corner.x - before.x), outgoing = atan2(after.y - corner.y, after.x - corner.x)
        // The ends of each side are fixed, their tangents only held by the deviation.
        #expect(abs(incoming - atan2(0, 1)) < 1e-2)
        #expect(abs(outgoing - atan2(-1, 1)) < 1e-2)
        let refitted = try SketchSplineCurve(degree: 3, knots: knots, controlPoints: result.curve.controlPoints, tolerance: .standard)
        #expect(try fitter.cornerParameters(of: refitted) == [knots[index + 1]])

        let smooth = try SketchSplineCurve(
            degree: 2, knots: [0, 0, 0, 0.5, 0.5, 1, 1, 1],
            controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 1, y: 2), Point2D(x: 2, y: 2), Point2D(x: 3, y: 2), Point2D(x: 4, y: 0)],
            tolerance: .standard
        )
        #expect(try fitter.cornerParameters(of: smooth).isEmpty)
    }

    /// A polyline's every turning vertex is a corner.
    @Test func aPolylinesTurningVerticesAreCorners() throws {
        let polyline = try SketchSplineCurve(
            degree: 1, knots: nil,
            controlPoints: [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0), Point2D(x: 2, y: 0), Point2D(x: 2, y: 1)],
            tolerance: .standard
        )
        #expect(try fitter.cornerParameters(of: polyline).count == 1)
        let result = try fitter.refit(polyline, deviation: 1e-6, keepsCorners: true)
        #expect(result.maximumDeviation <= 1e-6)
        #expect(result.curve.controlPoints.contains(Point2D(x: 2, y: 0)))
    }
}

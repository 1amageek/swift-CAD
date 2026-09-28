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
            previous = result.maximumDeviation
        }
        #expect(previous < 1e-3)
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
}

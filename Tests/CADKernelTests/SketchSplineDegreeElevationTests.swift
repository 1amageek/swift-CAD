import Testing
@testable import CADKernel
import CADCore
import CADIR

/// Raising a sketch spline's degree keeps its curve and its parameter.
@Suite struct SketchSplineDegreeElevationTests {
    @Test(arguments: [
        (3, nil as [Double]?, [(0.0, 0.0), (1.0, 2.0), (3.0, 2.0), (4.0, 0.0), (5.0, -2.0), (7.0, -1.0), (8.0, 1.0)]),
        (5, nil, [(0.0, 0.0), (1.0, 2.0), (2.0, -1.0), (3.0, 3.0), (4.0, 1.0), (5.0, 2.0)]),
        (3, [0, 0, 0, 0, 0.3, 1, 1, 1, 1], [(0.0, 0.0), (1.0, 1.0), (2.0, 1.5), (3.0, 0.2), (4.0, 1.0)]),
    ])
    func theRaisedSplineIsTheSameCurve(degree: Int, knots: [Double]?, points: [(Double, Double)]) throws {
        let curve = try SketchSplineCurve(degree: degree, knots: knots, controlPoints: points.map { Point2D(x: $0.0, y: $0.1) }, tolerance: .standard)
        let raised = try curve.degreeElevated(tolerance: .standard)
        #expect(raised.degree == degree + 1)
        #expect(raised.knots.first == curve.bSpline.knots.first && raised.knots.last == curve.bSpline.knots.last)
        let lower = curve.bSpline.knots.first!, upper = curve.bSpline.knots.last!
        for i in 0...200 {
            let u = lower + (upper - lower) * Double(i) / 200
            let a = try curve.bSpline.point(at: u, tolerance: .standard), b = try raised.point(at: u, tolerance: .standard)
            #expect(abs(a.x - b.x) <= 1e-12 && abs(a.y - b.y) <= 1e-12)
        }
    }
}

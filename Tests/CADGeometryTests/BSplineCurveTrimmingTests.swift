import CADCore
import CADGeometry
import Foundation
import Testing

@Suite("B-spline Curve Trimming")
struct BSplineCurveTrimmingTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func rationalQuadraticTrimsPreserveExactTwoAndThreeDimensionalEvaluation() throws {
        let knots = [0.0, 0.0, 0.0, 1.0, 1.0, 1.0]
        let weights = [1.0, 0.5, 2.0]
        let curve2D = BSplineCurve2D(
            degree: 2,
            knots: knots,
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.5, y: 1.0),
                Point2D(x: 1.0, y: 0.0),
            ],
            weights: weights
        )
        let curve3D = BSplineCurve3D(
            degree: 2,
            knots: knots,
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.5, y: 1.0, z: 0.25),
                Point3D(x: 1.0, y: 0.0, z: 1.0),
            ],
            weights: weights
        )

        let trimmed2D = try curve2D.trimmed(from: 0.25, to: 0.75, tolerance: tolerance)
        let trimmed3D = try curve3D.trimmed(from: 0.25, to: 0.75, tolerance: tolerance)

        #expect(trimmed2D.domain == .closed(0.25, 0.75))
        #expect(trimmed3D.domain == .closed(0.25, 0.75))
        #expect(trimmed2D.isRational)
        #expect(trimmed3D.isRational)
        for parameter in [0.25, 0.375, 0.5, 0.625, 0.75] {
            let original2D = try curve2D.point(at: parameter, tolerance: tolerance)
            let result2D = try trimmed2D.point(at: parameter, tolerance: tolerance)
            #expect(hypot(original2D.x - result2D.x, original2D.y - result2D.y) <= tolerance.distance)

            let original3D = try curve3D.point(at: parameter, tolerance: tolerance)
            let result3D = try trimmed3D.point(at: parameter, tolerance: tolerance)
            #expect(original3D.isApproximatelyEqual(to: result3D, tolerance: tolerance.distance))
        }
    }
}

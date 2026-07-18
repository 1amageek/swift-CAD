import CADCore
import CADGeometry
import Testing

@Suite("Surface Parameter Curve Differential")
struct SurfaceParameterCurveDifferentialTests {
    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineDerivativeUsesNormalizedCurveParameter() throws {
        let curve = BSplineCurve2D(
            degree: 2,
            knots: [2.0, 2.0, 2.0, 5.0, 5.0, 5.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 1.5, y: 2.0),
                Point2D(x: 4.0, y: -1.0),
            ],
            weights: [1.0, 0.75, 1.25]
        )
        let pcurve = SurfaceParameterCurve.bSpline(curve)
        let fraction = 0.4
        let step = 1.0e-6

        let differential = try pcurve.differentialGeometry(
            atNormalizedFraction: fraction,
            tolerance: .standard
        )
        let lower = try pcurve.parameter(
            atNormalizedFraction: fraction - step,
            tolerance: .standard
        )
        let upper = try pcurve.parameter(
            atNormalizedFraction: fraction + step,
            tolerance: .standard
        )
        let finiteDifference = Point2D(
            x: (upper.u - lower.u) / (2.0 * step),
            y: (upper.v - lower.v) / (2.0 * step)
        )

        #expect(abs(differential.firstDerivative.x - finiteDifference.x) <= 1.0e-8)
        #expect(abs(differential.firstDerivative.y - finiteDifference.y) <= 1.0e-8)
    }
}

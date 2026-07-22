import Foundation
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

    @Test(.timeLimit(.minutes(1)))
    func harmonicValidationRejectsDomainExcursionBetweenLegacySamples() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                ],
            ]
        ))
        let peakParameter = Double.pi / 32.0
        let amplitude = 0.5001
        let curve = SurfaceParameterCurve.harmonic(
            center: Point2D(x: 0.5, y: 0.5),
            cosine: Point2D(
                x: amplitude * cos(peakParameter),
                y: 0.0
            ),
            sine: Point2D(
                x: amplitude * sin(peakParameter),
                y: 0.0
            ),
            startParameter: 0.0,
            endParameter: 2.0 * Double.pi
        )

        #expect(throws: GeometryError.self) {
            try curve.validate(on: surface, tolerance: .standard)
        }
    }
}

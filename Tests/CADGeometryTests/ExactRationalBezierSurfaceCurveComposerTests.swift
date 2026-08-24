import Testing
import Foundation

import CADCore
@testable import CADGeometry

@Suite("Exact rational Bezier surface-curve composition")
struct ExactRationalBezierSurfaceCurveComposerTests {
    @Test(.timeLimit(.minutes(1)))
    func composesRoundedParameterArcWithoutResidualOrDerivativeInflation() throws {
        let surface = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 2.0, y: 0.0, z: 0.1),
            topRight: Point3D(x: 2.0, y: 1.5, z: 0.4),
            topLeft: Point3D(x: 0.0, y: 1.5, z: 0.0)
        )
        let parameterCurve = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.25),
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.25, y: 0.0),
            ],
            weights: [1.0, sqrt(0.5), 1.0]
        )
        let exact = try ExactRationalBezierSurfaceCurveComposer().compose(
            surface: surface,
            parameterCurve: parameterCurve,
            tolerance: .standard
        )
        let lift = SurfaceLiftCurve3D(
            surface: .bSpline(surface),
            parameterCurve: .bSpline(parameterCurve),
            exactBSplineImage: exact
        )

        #expect(exact.degree == 12)
        let minimumWeight = try #require(exact.weights.min())
        let maximumWeight = try #require(exact.weights.max())
        #expect(maximumWeight / minimumWeight < 16.0)
        for fraction in stride(from: 0.0, through: 1.0, by: 0.0625) {
            let parameter = try parameterCurve.point(
                at: fraction,
                tolerance: .standard
            )
            let expected = try surface.point(
                u: parameter.x,
                v: parameter.y,
                tolerance: .standard
            )
            let actual = try exact.point(at: fraction, tolerance: .standard)
            #expect(actual.isApproximatelyEqual(to: expected, tolerance: 1.0e-10))
        }
        for interval in [
            try ScalarInterval(lower: 0.0, upper: 1.0),
            try ScalarInterval(lower: 0.0, upper: 0.5),
            try ScalarInterval(lower: 0.0, upper: 0.01),
        ] {
            let optionalSecond = try SurfaceLiftDifferentialBounder().secondDerivativeMagnitude(
                lift: lift,
                interval: interval,
                tolerance: .standard
            )
            let second = try #require(optionalSecond)
            #expect(second < 32.0)
        }
    }
}

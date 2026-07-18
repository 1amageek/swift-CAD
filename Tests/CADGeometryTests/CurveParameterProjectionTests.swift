import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Curve Parameter Projection")
struct CurveParameterProjectionTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func analyticCurvesRecoverExactParameters() throws {
        let curves: [(Curve3D, Double)] = [
            (
                .line(Line3D(
                    origin: Point3D(x: 1.0, y: 2.0, z: 3.0),
                    direction: .unitX
                )),
                4.25
            ),
            (
                .circle(Circle3D(center: .origin, normal: .unitZ, radius: 2.0)),
                1.25
            ),
            (
                .analytic(.ellipse(
                    center: Point3D(x: 0.5, y: -0.25, z: 0.0),
                    normal: .unitZ,
                    majorAxis: .unitX,
                    majorRadius: 3.0,
                    minorRadius: 1.5
                )),
                5.5
            ),
            (
                .analytic(.arc(
                    center: .origin,
                    normal: .unitZ,
                    radius: 4.0,
                    startAngle: 0.5,
                    endAngle: 2.5
                )),
                1.75
            ),
        ]

        for (curve, parameter) in curves {
            let point = try curve.point(at: parameter, tolerance: tolerance)
            let projection = try curve.parameterProjection(of: point, tolerance: tolerance)
            #expect(abs(projection.parameter - parameter) <= tolerance.angle)
            #expect(projection.residual <= tolerance.distance)
            #expect(projection.iterations == 0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineProjectionUsesBoundedNewtonRefinement() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 2.0, z: 0.0),
                Point3D(x: 3.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.75, 1.25]
        ))
        let parameter = 0.37
        let point = try curve.point(at: parameter, tolerance: tolerance)

        let projection = try curve.parameterProjection(
            of: point,
            options: CurveParameterProjectionOptions(
                maximumIterations: 48,
                seedCount: 96
            ),
            tolerance: tolerance
        )

        #expect(abs(projection.parameter - parameter) <= tolerance.angle)
        #expect(projection.residual <= tolerance.distance)
        #expect(projection.iterations > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func offCurvePointReturnsTypedResidualFailure() throws {
        let curve = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        do {
            _ = try curve.parameterProjection(
                of: Point3D(x: 1.0, y: 1.0, z: 0.0),
                tolerance: tolerance
            )
            Issue.record("Off-curve points must not produce an unverified parameter.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .intersectionFailure)
            #expect(error.residual == 1.0)
            #expect(error.tolerance == tolerance)
        }
    }
}

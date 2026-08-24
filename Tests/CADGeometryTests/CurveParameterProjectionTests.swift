import CADCore
@testable import CADGeometry
import Foundation
import Testing

@Suite("Curve Parameter Projection")
struct CurveParameterProjectionTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func closestProjectionCertifiesTrimmedEndpointMinimum() throws {
        let curve = Curve3D.line(Line3D(
            origin: .origin,
            direction: .unitX
        ))
        let projection = try curve.closestParameterProjection(
            of: Point3D(x: 3.0, y: 2.0, z: 0.0),
            options: CurveParameterProjectionOptions(
                parameterRange: try ScalarInterval(lower: 0.0, upper: 1.0)
            ),
            tolerance: tolerance
        )

        #expect(abs(projection.parameter - 1.0) <= tolerance.relative)
        #expect(projection.point.isApproximatelyEqual(
            to: Point3D(x: 1.0, y: 0.0, z: 0.0),
            tolerance: tolerance.distance
        ))
        #expect(abs(projection.residual - hypot(2.0, 2.0)) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func closestProjectionCertifiesCurvedInteriorMinimum() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -1.0, y: 1.0, z: 0.0),
                Point3D(x: 0.0, y: -1.0, z: 0.0),
                Point3D(x: 1.0, y: 1.0, z: 0.0),
            ]
        ))
        let target = try curve.point(at: 0.5, tolerance: tolerance)
        let projection = try curve.closestParameterProjection(
            of: target + Vector3D(x: 0.0, y: 0.1, z: 0.0),
            options: CurveParameterProjectionOptions(
                parameterRange: try ScalarInterval(lower: 0.0, upper: 1.0)
            ),
            tolerance: tolerance
        )

        #expect(abs(projection.parameter - 0.5) <= tolerance.relative * 64.0)
        #expect(projection.point.isApproximatelyEqual(
            to: target,
            tolerance: tolerance.distance
        ))
        #expect(abs(projection.residual - 0.1) <= tolerance.distance)
    }

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
    func exactLinearRationalBSplineProjectionUsesClosedFormParameter() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [2.0, 2.0, 5.0, 5.0],
            controlPoints: [
                Point3D(x: -1.0, y: 2.0, z: 0.5),
                Point3D(x: 4.0, y: -3.0, z: 2.5),
            ],
            weights: [0.6, 1.8]
        ))
        let parameter = 3.2
        let point = try curve.point(at: parameter, tolerance: tolerance)
        let projection = try curve.parameterProjection(
            of: point,
            options: CurveParameterProjectionOptions(
                parameterRange: try ScalarInterval(lower: 3.0, upper: 4.0)
            ),
            tolerance: tolerance
        )

        #expect(abs(projection.parameter - parameter) <= tolerance.relative)
        #expect(projection.residual <= tolerance.distance)
        #expect(projection.iterations == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func exactLinearBSplineProjectionRejectsPointOutsideRequestedSpan() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 10.0, y: 0.0, z: 0.0),
            ]
        ))

        do {
            _ = try curve.parameterProjection(
                of: Point3D(x: 8.0, y: 0.0, z: 0.0),
                options: CurveParameterProjectionOptions(
                    parameterRange: try ScalarInterval(lower: 0.0, upper: 0.5)
                ),
                tolerance: tolerance
            )
            Issue.record("An exact linear projection outside the requested trim must fail explicitly.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .intersectionFailure)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineProjectionReturnsTypedParameterAmbiguity() throws {
        let bSpline = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: -1.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ]
        )
        let curve = Curve3D.bSpline(bSpline)

        do {
            _ = try bSpline.differentialGeometry(at: 0.5, tolerance: tolerance)
            Issue.record("A singular B-spline parameter must not return a fabricated tangent.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularSystem)
            #expect(error.residual.map { $0 <= tolerance.distance } == true)
            #expect(error.tolerance == tolerance)
        }

        do {
            _ = try curve.parameterProjection(
                of: Point3D(x: 0.25, y: 0.0, z: 0.0),
                tolerance: tolerance
            )
            Issue.record("A self-overlapping B-spline curve must not silently choose one parameter root.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .ambiguousSelection)
            #expect(error.residual.map { $0 <= tolerance.distance } == true)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func closedBSplineProjectionCanonicalizesEquivalentSeamParameters() throws {
        let bSpline = BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 0.25, 0.5, 0.75, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 1.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0),
                Point3D(x: 0.0, y: 0.0, z: 0.0),
            ]
        )
        let seamPoint = try bSpline.point(at: 0.0, tolerance: tolerance)

        let projection = try Curve3D.bSpline(bSpline).parameterProjection(
            of: seamPoint,
            tolerance: tolerance
        )

        #expect(abs(projection.parameter) <= tolerance.relative)
        #expect(projection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonClampedRationalBSplineProjectionCoversTheNaturalDomain() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.4, z: 0.2),
                Point3D(x: 2.0, y: -0.2, z: 0.5),
                Point3D(x: 3.0, y: 0.3, z: 0.8),
            ],
            weights: [1.0, 0.8, 1.2, 1.0]
        ))
        let expectedParameter = 3.37
        let point = try curve.point(at: expectedParameter, tolerance: tolerance)

        let projection = try curve.parameterProjection(
            of: point,
            tolerance: tolerance
        )
        #expect(abs(projection.parameter - expectedParameter) <= tolerance.angle)
        #expect(projection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineProjectionEnforcesSubdivisionBudget() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 2.0, z: 0.0),
                Point3D(x: 3.0, y: 0.0, z: 0.0),
            ]
        ))
        let point = try curve.point(at: 0.37, tolerance: tolerance)

        do {
            _ = try curve.parameterProjection(
                of: point,
                options: CurveParameterProjectionOptions(
                    maximumSubdivisionCells: 1,
                    maximumCandidateCount: 1
                ),
                tolerance: tolerance
            )
            Issue.record("B-spline inverse projection must enforce its explicit cell budget.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual != nil)
            #expect(error.tolerance == tolerance)
        }
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

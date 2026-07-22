import Testing
import CADCore
import CADGeometry
import Foundation

@Suite("Certified curve-surface correspondence")
struct CurveSurfaceCorrespondenceValidatorTests {
    private let options = CurveSurfaceCorrespondenceValidationOptions(
        maximumSubdivisionDepth: 32,
        maximumCellCount: 65_536
    )

    @Test(.timeLimit(.minutes(1)))
    func acceptsAnalyticCylinderCoordinateCircle() throws {
        let surface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 2.0
        ))
        let curve = Curve3D.analytic(.arc(
            center: .origin,
            normal: .unitZ,
            radius: 2.0,
            startAngle: 0.0,
            endAngle: Double.pi * 0.5
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: 0.0,
            to: Double.pi * 0.5,
            surface: surface,
            parameterCurve: .constantV(
                v: 0.0,
                uStart: 0.0,
                uEnd: Double.pi * 0.5
            ),
            options: options,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptsAnalyticHyperbolaWithExactRationalPcurve() throws {
        let parameterLimit = 0.75
        let transverseRadius = 2.0
        let conjugateRadius = 1.5
        let middleWeight = cosh(parameterLimit)
        let surface = Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.analytic(.hyperbola(Hyperbola3D(
            center: .origin,
            normal: .unitZ,
            transverseAxis: .unitX,
            transverseRadius: transverseRadius,
            conjugateRadius: conjugateRadius
        )))
        let parameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(
                    x: -conjugateRadius * sinh(parameterLimit),
                    y: -transverseRadius * cosh(parameterLimit)
                ),
                Point2D(x: 0.0, y: -transverseRadius / middleWeight),
                Point2D(
                    x: conjugateRadius * sinh(parameterLimit),
                    y: -transverseRadius * cosh(parameterLimit)
                ),
            ],
            weights: [1.0, middleWeight, 1.0]
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: -parameterLimit,
            to: parameterLimit,
            surface: surface,
            parameterCurve: parameterCurve,
            options: options,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptsAnalyticParabolaWithExactPolynomialPcurve() throws {
        let focalLength = 1.0
        let endpointHeight = 1.0 / (4.0 * focalLength)
        let surface = Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.analytic(.parabola(Parabola3D(
            vertex: .origin,
            normal: .unitZ,
            axis: .unitY,
            focalLength: focalLength
        )))
        let parameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: endpointHeight, y: -1.0),
                Point2D(x: -endpointHeight, y: 0.0),
                Point2D(x: endpointHeight, y: 1.0),
            ]
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: -1.0,
            to: 1.0,
            surface: surface,
            parameterCurve: parameterCurve,
            options: options,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func planeTorusCurveRequiresAndAcceptsItsStructuralPcurve() throws {
        let plane = Surface3D.plane(Plane3D(
            origin: Point3D(x: 3.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))
        let torus = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let intersections = try DefaultSurfaceSurfaceIntersector().intersections(
            first: plane,
            second: torus,
            tolerance: .standard
        )
        guard case let .curve(result) = try #require(intersections.first),
              case .analytic(.planeTorus) = result.curve else {
            Issue.record("An offset plane-torus section must produce an exact algebraic curve.")
            return
        }
        let upper = 2.0 * Double.pi
        let validator = DefaultCurveSurfaceCorrespondenceValidator()
        try validator.validate(
            curve: result.curve,
            from: 0.0,
            to: upper,
            surface: plane,
            parameterCurve: result.firstSurfaceParameterCurve,
            options: options,
            tolerance: .standard
        )

        do {
            try validator.validate(
                curve: result.curve,
                from: 0.0,
                to: upper,
                surface: plane,
                parameterCurve: .polyline([
                    SurfaceParameter(u: 0.0, v: 0.0),
                    SurfaceParameter(u: 1.0, v: 0.0),
                ]),
                options: options,
                tolerance: .standard
            )
            Issue.record("A plane-torus curve accepted an unrelated non-certified pcurve.")
        } catch let error as KernelError {
            #expect(error.code == .topologyFailure)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsPolylineExcursionHiddenBetweenFixedSamples() throws {
        let surface = Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.analytic(.line(
            origin: .origin,
            direction: .unitX
        ))
        let parameterCurve = SurfaceParameterCurve.polyline([
            SurfaceParameter(u: 0.0, v: 0.0),
            SurfaceParameter(u: 0.030, v: 0.0),
            SurfaceParameter(u: 0.031, v: 0.001),
            SurfaceParameter(u: 0.032, v: 0.0),
            SurfaceParameter(u: 1.0, v: 0.0),
        ])

        #expect(throws: KernelError.self) {
            try DefaultCurveSurfaceCorrespondenceValidator().validate(
                curve: curve,
                from: 0.0,
                to: 1.0,
                surface: surface,
                parameterCurve: parameterCurve,
                options: options,
                tolerance: .standard
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptsNonAffineRationalBSplinePcurveWithCertifiedBounds() throws {
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.line(Line3D(
            origin: .origin,
            direction: .unitX
        ))
        let parameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.2, y: 0.0),
                Point2D(x: 1.0, y: 0.0),
            ],
            weights: [1.0, 0.75, 1.0]
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: 0.0,
            to: 1.0,
            surface: surface,
            parameterCurve: parameterCurve,
            options: options,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsRationalBSplinePcurveExcursion() throws {
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.line(Line3D(
            origin: .origin,
            direction: .unitX
        ))
        let parameterCurve = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.2, y: 0.01),
                Point2D(x: 1.0, y: 0.0),
            ],
            weights: [1.0, 0.75, 1.0]
        ))

        #expect(throws: KernelError.self) {
            try DefaultCurveSurfaceCorrespondenceValidator().validate(
                curve: curve,
                from: 0.0,
                to: 1.0,
                surface: surface,
                parameterCurve: parameterCurve,
                options: options,
                tolerance: .standard
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptsNonAffineRationalBSplineEdgeWithCertifiedBounds() throws {
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                .origin,
                Point3D(x: 0.2, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.75, 1.0]
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: 0.0,
            to: 1.0,
            surface: surface,
            parameterCurve: .affine(
                origin: Point2D(x: 0.0, y: 0.0),
                direction: Point2D(x: 1.0, y: 0.0),
                startParameter: 0.0,
                endParameter: 1.0
            ),
            options: options,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func affineBilinearSurfaceCertifiesExactRationalBSplinePcurveStructurally() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 1.0, y: 2.0, z: 3.0),
                    Point3D(x: 3.0, y: 2.0, z: 3.0),
                ],
                [
                    Point3D(x: 1.0, y: 5.0, z: 3.0),
                    Point3D(x: 3.0, y: 5.0, z: 3.0),
                ],
            ]
        ))
        let parameterCurve = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.1, y: 0.2),
                Point2D(x: 0.5, y: 0.9),
                Point2D(x: 0.8, y: 0.3),
            ],
            weights: [1.0, 0.65, 1.0]
        )
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: parameterCurve.degree,
            knots: parameterCurve.knots,
            controlPoints: parameterCurve.controlPoints.map {
                Point3D(x: 1.0 + 2.0 * $0.x, y: 2.0 + 3.0 * $0.y, z: 3.0)
            },
            weights: parameterCurve.weights
        ))

        try DefaultCurveSurfaceCorrespondenceValidator().validate(
            curve: curve,
            from: 0.0,
            to: 1.0,
            surface: surface,
            parameterCurve: .bSpline(parameterCurve),
            options: CurveSurfaceCorrespondenceValidationOptions(
                maximumSubdivisionDepth: 1,
                maximumCellCount: 1
            ),
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func affineBilinearSurfaceRejectsMismatchedRationalBSplinePcurve() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [.origin, Point3D(x: 2.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 3.0, z: 0.0), Point3D(x: 2.0, y: 3.0, z: 0.0)],
            ]
        ))
        let parameterCurve = BSplineCurve2D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 0.0, y: 0.0),
                Point2D(x: 0.5, y: 0.75),
                Point2D(x: 1.0, y: 1.0),
            ],
            weights: [1.0, 0.8, 1.0]
        )
        let mismatchedCurve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: parameterCurve.knots,
            controlPoints: [
                .origin,
                Point3D(x: 1.0, y: 2.20, z: 0.0),
                Point3D(x: 2.0, y: 3.0, z: 0.0),
            ],
            weights: parameterCurve.weights
        ))

        #expect(throws: KernelError.self) {
            try DefaultCurveSurfaceCorrespondenceValidator().validate(
                curve: mismatchedCurve,
                from: 0.0,
                to: 1.0,
                surface: surface,
                parameterCurve: .bSpline(parameterCurve),
                options: options,
                tolerance: .standard
            )
        }
    }
}

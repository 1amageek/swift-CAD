import CADCore
import CADGeometry
import Foundation
import Testing

@Suite("Curve-Surface Intersection")
struct CurveSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func lineSphereProducesVerifiedTransverseIntersections() throws {
        let curve = Curve3D.line(Line3D(origin: Point3D(x: -2.0, y: 0.0, z: 0.0), direction: .unitX))
        let surface = Surface3D.analytic(.sphere(center: .origin, radius: 1.0))
        let options = CurveSurfaceIntersectionOptions(
            curveRange: try ScalarInterval(lower: 0.0, upper: 4.0)
        )

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        #expect(abs(intersections[0].curveParameter - 1.0) <= tolerance.distance)
        #expect(abs(intersections[1].curveParameter - 3.0) <= tolerance.distance)
        #expect(intersections.allSatisfy { $0.kind == .transverse })
        #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
    }

    @Test(.timeLimit(.minutes(1)))
    func tangentLineSphereProducesSingleTangentIntersection() throws {
        let curve = Curve3D.line(Line3D(origin: Point3D(x: -2.0, y: 1.0, z: 0.0), direction: .unitX))
        let surface = Surface3D.analytic(.sphere(center: .origin, radius: 1.0))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: CurveSurfaceIntersectionOptions(
                curveRange: try ScalarInterval(lower: 0.0, upper: 4.0)
            ),
            tolerance: tolerance
        )

        #expect(intersections.count == 1)
        #expect(intersections[0].kind == .tangent)
        #expect(intersections[0].point.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: 1.0, z: 0.0),
            tolerance: tolerance.distance
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticPlaneLiftIntersectsSphereThroughExactReduction() throws {
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: .analytic(.plane(origin: .origin, normal: .unitZ)),
            parameterCurve: .affine(
                origin: Point2D(x: -2.0, y: 0.0),
                direction: Point2D(x: 1.0, y: 0.0),
                startParameter: 0.0,
                endParameter: 4.0
            )
        ))
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: .analytic(.sphere(center: .origin, radius: 1.0)),
            options: .init(),
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        #expect(intersections.allSatisfy { $0.kind == .transverse })
        #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
        #expect(abs(intersections[0].curveParameter - 0.25) <= tolerance.angle)
        #expect(abs(intersections[1].curveParameter - 0.75) <= tolerance.angle)
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticCylinderGeneratorLiftIntersectsPlaneThroughExactReduction() throws {
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: .analytic(.cylinder(
                origin: .origin,
                axis: .unitZ,
                radius: 2.0
            )),
            parameterCurve: .constantU(
                u: 0.0,
                vStart: -2.0,
                vEnd: 2.0
            )
        ))
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: .analytic(.plane(origin: .origin, normal: .unitZ)),
            options: .init(),
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        #expect(intersection.kind == .transverse)
        #expect(intersection.residual <= tolerance.distance)
        #expect(abs(intersection.curveParameter - 0.5) <= tolerance.angle)
    }

    @Test(.timeLimit(.minutes(1)))
    func sphericalGreatCircleLiftIntersectsPlaneThroughExactReduction() throws {
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: .analytic(.sphere(center: .origin, radius: 2.0)),
            parameterCurve: .sphericalGreatCircle(
                cosine: .unitX,
                sine: .unitY,
                startParameter: 0.0,
                endParameter: 2.0 * Double.pi
            )
        ))
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: .analytic(.plane(origin: .origin, normal: .unitX)),
            options: .init(),
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        #expect(intersections.allSatisfy { $0.kind == .transverse })
        #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
    }

    @Test(.timeLimit(.minutes(1)))
    func torusCoordinateLiftIntersectsPlaneThroughExactReduction() throws {
        let curve = Curve3D.surfaceLift(SurfaceLiftCurve3D(
            surface: .analytic(.torus(
                center: .origin,
                axis: .unitZ,
                majorRadius: 3.0,
                minorRadius: 1.0
            )),
            parameterCurve: .constantV(
                v: 0.0,
                uStart: 0.0,
                uEnd: 2.0 * Double.pi
            )
        ))
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: .analytic(.plane(
                origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
                normal: .unitX
            )),
            options: .init(),
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        #expect(intersections.allSatisfy { $0.kind == .transverse })
        #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
    }

    @Test(.timeLimit(.minutes(1)))
    func coincidentLinePlaneReturnsTypedNonDiscreteDiagnostic() throws {
        let curve = Curve3D.line(Line3D(origin: .origin, direction: .unitX))
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))

        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: surface,
                options: CurveSurfaceIntersectionOptions(
                    curveRange: try ScalarInterval(lower: 0.0, upper: 1.0)
                ),
                tolerance: tolerance
            )
            Issue.record("A continuous intersection must not be returned as discrete points.")
        } catch let error as KernelError {
            #expect(error.code == .nonDiscreteIntersection)
            #expect(error.phase == .geometry)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func circlePlaneProducesVerifiedClosedFormIntersections() throws {
        let curve = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 2.0
        ))
        let surface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        #expect(intersections.allSatisfy { $0.kind == .transverse })
        #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
        #expect(intersections.allSatisfy { abs($0.point.x - 1.0) <= tolerance.distance })
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicCircleRootIsLiftedIntoNegativeTrimRange() throws {
        let curve = Curve3D.analytic(.circle(
            center: .origin,
            normal: -Vector3D.unitX,
            radius: 3.0
        ))
        let surface = Surface3D.analytic(.cylinder(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            axis: .unitZ,
            radius: 1.5
        ))
        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: CurveSurfaceIntersectionOptions(
                curveRange: try ScalarInterval(
                    lower: -Double.pi * 0.5,
                    upper: 0.0
                )
            ),
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        #expect(intersection.curveParameter < 0.0)
        #expect(intersection.curveParameter >= -Double.pi * 0.5)
        #expect(intersection.point.y > 0.0)
        #expect(intersection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func coincidentCirclePlaneReturnsTypedNonDiscreteDiagnostic() throws {
        let curve = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 2.0
        ))
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))

        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: surface,
                options: .init(),
                tolerance: tolerance
            )
            Issue.record("A coincident circular curve must not be returned as discrete points.")
        } catch let error as KernelError {
            #expect(error.code == .nonDiscreteIntersection)
            #expect(error.phase == .geometry)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func ellipsePlaneProducesVerifiedClosedFormIntersections() throws {
        let curve = Curve3D.analytic(.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 2.0,
            minorRadius: 1.0
        ))
        let surface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        #expect(intersections.allSatisfy { $0.kind == .transverse })
        #expect(intersections.allSatisfy { $0.iterations == 0 })
        #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
        #expect(intersections.allSatisfy {
            abs($0.point.x - 1.0) <= tolerance.distance
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func tangentEllipsePlaneProducesSingleClosedFormIntersection() throws {
        let curve = Curve3D.analytic(.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 2.0,
            minorRadius: 1.0
        ))
        let surface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        #expect(intersection.kind == .tangent)
        #expect(intersection.iterations == 0)
        #expect(intersection.point.isApproximatelyEqual(
            to: Point3D(x: 2.0, y: 0.0, z: 0.0),
            tolerance: tolerance.distance
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func ellipsePlaneClosedFormHonorsCurveRange() throws {
        let curve = Curve3D.analytic(.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 2.0,
            minorRadius: 1.0
        ))
        let surface = Surface3D.plane(Plane3D(
            origin: Point3D(x: 1.0, y: 0.0, z: 0.0),
            normal: .unitX
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: CurveSurfaceIntersectionOptions(
                curveRange: try ScalarInterval(lower: 0.0, upper: Double.pi)
            ),
            tolerance: tolerance
        )

        #expect(intersections.count == 1)
        #expect(intersections[0].curveParameter <= Double.pi)
    }

    @Test(.timeLimit(.minutes(1)))
    func coincidentEllipsePlaneReturnsTypedNonDiscreteDiagnostic() throws {
        let curve = Curve3D.analytic(.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 2.0,
            minorRadius: 1.0
        ))
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))

        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: surface,
                options: .init(),
                tolerance: tolerance
            )
            Issue.record("A coincident elliptic curve must not be returned as discrete points.")
        } catch let error as KernelError {
            #expect(error.code == .nonDiscreteIntersection)
            #expect(error.phase == .geometry)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func circleSphereProducesVerifiedAlgebraicIntersections() throws {
        let curve = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 2.0
        ))
        let surface = Surface3D.analytic(.sphere(
            center: Point3D(x: 1.0, y: 0.0, z: 0.0),
            radius: sqrt(3.0)
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance
        )

        #expect(intersections.count == 2)
        #expect(intersections.allSatisfy { $0.kind == .transverse })
        #expect(intersections.allSatisfy { $0.iterations == 0 })
        #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
        #expect(intersections.allSatisfy {
            abs($0.point.x - 1.0) <= tolerance.distance
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func tangentCircleSphereProducesSingleAlgebraicIntersection() throws {
        let curve = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 2.0
        ))
        let surface = Surface3D.analytic(.sphere(
            center: Point3D(x: 3.0, y: 0.0, z: 0.0),
            radius: 1.0
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        #expect(intersection.kind == .tangent)
        #expect(intersection.iterations == 0)
        #expect(intersection.point.isApproximatelyEqual(
            to: Point3D(x: 2.0, y: 0.0, z: 0.0),
            tolerance: tolerance.distance
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func ellipseCylinderProducesFourVerifiedAlgebraicIntersections() throws {
        let curve = Curve3D.analytic(.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 2.0,
            minorRadius: 1.0
        ))
        let surface = Surface3D.cylinder(Cylinder3D(
            origin: .origin,
            axis: .unitY,
            radius: 1.5
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance
        )

        #expect(intersections.count == 4)
        #expect(intersections.allSatisfy { $0.kind == .transverse })
        #expect(intersections.allSatisfy { $0.iterations == 0 })
        #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
        #expect(intersections.allSatisfy {
            abs(abs($0.point.x) - 1.5) <= tolerance.distance
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func circleTorusProducesFourVerifiedDegreeEightIntersections() throws {
        let curve = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitY,
            radius: 3.0
        ))
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance
        )

        #expect(intersections.count == 4)
        #expect(intersections.allSatisfy { $0.kind == .transverse })
        #expect(intersections.allSatisfy { $0.iterations == 0 })
        #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
        #expect(intersections.allSatisfy {
            abs(abs($0.point.x) - 17.0 / 6.0) <= tolerance.distance
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func coincidentCircleSphereReturnsTypedNonDiscreteDiagnostic() throws {
        let curve = Curve3D.circle(Circle3D(
            center: .origin,
            normal: .unitZ,
            radius: 2.0
        ))
        let surface = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 2.0
        ))

        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: surface,
                options: .init(),
                tolerance: tolerance
            )
            Issue.record("A circle contained by a sphere must report a non-discrete intersection.")
        } catch let error as KernelError {
            #expect(error.code == .nonDiscreteIntersection)
            #expect(error.phase == .geometry)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unboundedHyperbolaIntersectsEveryAnalyticSurfaceWithoutFiniteRangeFallback() throws {
        let curve = Curve3D.analytic(.hyperbola(Hyperbola3D(
            center: .origin,
            normal: .unitZ,
            transverseAxis: .unitX,
            transverseRadius: 1.0,
            conjugateRadius: 1.0
        )))
        let cases: [(surface: Surface3D, expectedCount: Int)] = [
            (
                .plane(Plane3D(
                    origin: Point3D(x: 2.0, y: 0.0, z: 0.0),
                    normal: .unitX
                )),
                2
            ),
            (
                .analytic(.cylinder(origin: .origin, axis: .unitZ, radius: 2.0)),
                2
            ),
            (
                .analytic(.cone(
                    apex: .origin,
                    axis: .unitX,
                    halfAngle: atan(0.5)
                )),
                2
            ),
            (
                .analytic(.sphere(center: .origin, radius: 2.0)),
                2
            ),
            (
                .analytic(.torus(
                    center: .origin,
                    axis: .unitZ,
                    majorRadius: 2.0,
                    minorRadius: 0.5
                )),
                4
            ),
        ]

        for item in cases {
            let intersections = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: item.surface,
                options: .init(),
                tolerance: tolerance
            )
            #expect(intersections.count == item.expectedCount)
            #expect(intersections.allSatisfy { $0.iterations == 0 })
            #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func unboundedParabolaIntersectsEveryAnalyticSurfaceWithCertifiedRangeFiltering() throws {
        let curve = Curve3D.analytic(.parabola(Parabola3D(
            vertex: .origin,
            normal: .unitZ,
            axis: .unitX,
            focalLength: 0.5
        )))
        let unrestrictedCases: [(surface: Surface3D, expectedCount: Int)] = [
            (
                .plane(Plane3D(origin: .origin, normal: .unitY)),
                1
            ),
            (
                .cylinder(Cylinder3D(origin: .origin, axis: .unitZ, radius: 1.0)),
                2
            ),
            (
                .analytic(.sphere(center: .origin, radius: 1.0)),
                2
            ),
            (
                .analytic(.torus(
                    center: .origin,
                    axis: .unitZ,
                    majorRadius: 2.0,
                    minorRadius: 0.5
                )),
                4
            ),
        ]

        for item in unrestrictedCases {
            let intersections = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: item.surface,
                options: .init(),
                tolerance: tolerance
            )
            #expect(intersections.count == item.expectedCount)
            #expect(intersections.allSatisfy { $0.iterations == 0 })
            #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
        }

        let coneIntersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: .analytic(.cone(
                apex: .origin,
                axis: .unitX,
                halfAngle: Double.pi * 0.25
            )),
            options: CurveSurfaceIntersectionOptions(
                curveRange: try ScalarInterval(lower: 1.0, upper: 3.0)
            ),
            tolerance: tolerance
        )
        let coneIntersection = try #require(coneIntersections.first)
        #expect(coneIntersections.count == 1)
        #expect(abs(coneIntersection.curveParameter - 2.0) <= tolerance.distance)
        #expect(coneIntersection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func adaptiveBSplineIntersectionRefinesAndVerifiesResidual() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.5, y: 0.5, z: -1.0),
                Point3D(x: 0.5, y: 0.5, z: 1.0),
            ],
            weights: [1.0, 2.0]
        ))
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ],
            weights: [[1.0, 1.5], [2.0, 1.0]]
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: CurveSurfaceIntersectionOptions(maximumSubdivisionDepth: 8),
            tolerance: tolerance
        )

        #expect(intersections.count == 1)
        #expect(intersections[0].point.isApproximatelyEqual(
            to: Point3D(x: 0.5, y: 0.5, z: 0.0),
            tolerance: tolerance.distance
        ))
        #expect(intersections[0].residual <= tolerance.distance)
        #expect(intersections[0].iterations > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticArcAgainstRationalSurfaceUsesExactCertifiedLocus() throws {
        let curve = Curve3D.analytic(.arc(
            center: .origin,
            normal: .unitZ,
            radius: 1.0,
            startAngle: 0.2,
            endAngle: 2.0
        ))
        let surface = rationalVerticalPlane(x: -0.6)

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(
                maximumSubdivisionDepth: 20,
                maximumSubdivisionCells: 262_144,
                maximumCandidateCount: 4_096
            ),
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        #expect(abs(intersection.curveParameter - asin(0.6)) <= tolerance.angle)
        #expect(intersection.point.isApproximatelyEqual(
            to: Point3D(x: -0.6, y: 0.8, z: 0.0),
            tolerance: tolerance.distance
        ))
        #expect(intersection.kind == .transverse)
        #expect(intersection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticEllipseAgainstRationalSurfaceRecoversBothSourceParameters() throws {
        let curve = Curve3D.analytic(.ellipse(
            center: .origin,
            normal: .unitZ,
            majorAxis: .unitX,
            majorRadius: 2.0,
            minorRadius: 1.0
        ))
        let surface = rationalVerticalPlane(x: 0.5)

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(
                maximumSubdivisionDepth: 20,
                maximumSubdivisionCells: 262_144,
                maximumCandidateCount: 4_096
            ),
            tolerance: tolerance
        )

        let expectedFirst = acos(0.25)
        let expectedSecond = 2.0 * Double.pi - expectedFirst
        #expect(intersections.count == 2)
        #expect(abs(intersections[0].curveParameter - expectedFirst) <= tolerance.angle)
        #expect(abs(intersections[1].curveParameter - expectedSecond) <= tolerance.angle)
        #expect(intersections.allSatisfy { $0.residual <= tolerance.distance })
        #expect(intersections.allSatisfy { $0.kind == .transverse })
    }

    @Test(.timeLimit(.minutes(1)))
    func shiftedPeriodicCircleAndLineUseTheSameCertifiedRationalSurfacePath() throws {
        let surface = rationalVerticalPlane(x: 0.3)
        let shiftedRange = try ScalarInterval(
            lower: 2.0 * Double.pi,
            upper: 4.0 * Double.pi
        )
        let circleIntersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: .circle(Circle3D(center: .origin, normal: .unitZ, radius: 1.0)),
            surface: surface,
            options: .init(
                curveRange: shiftedRange,
                maximumSubdivisionDepth: 20,
                maximumSubdivisionCells: 262_144,
                maximumCandidateCount: 4_096
            ),
            tolerance: tolerance
        )
        let expectedFirst = 2.0 * Double.pi + acos(0.3)
        let expectedSecond = 4.0 * Double.pi - acos(0.3)
        #expect(circleIntersections.count == 2)
        #expect(abs(circleIntersections[0].curveParameter - expectedFirst) <= tolerance.angle)
        #expect(abs(circleIntersections[1].curveParameter - expectedSecond) <= tolerance.angle)

        let lineIntersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: .line(Line3D(
                origin: Point3D(x: -1.0, y: 0.0, z: 0.0),
                direction: .unitX
            )),
            surface: surface,
            options: .init(curveRange: try ScalarInterval(lower: 0.0, upper: 2.0)),
            tolerance: tolerance
        )
        let lineIntersection = try #require(lineIntersections.first)
        #expect(lineIntersections.count == 1)
        #expect(abs(lineIntersection.curveParameter - 1.3) <= tolerance.distance)
        #expect(lineIntersection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplinePairSearchesEveryCurveKnotSpan() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 0.25, 0.5, 0.75, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -2.0, y: 0.25, z: 1.0),
                Point3D(x: -1.0, y: 0.25, z: 1.0),
                Point3D(x: 0.0, y: 0.25, z: 1.0),
                Point3D(x: 1.0, y: 0.25, z: 1.0),
                Point3D(x: 2.0, y: 0.25, z: -1.0),
            ],
            weights: [1.0, 0.8, 1.2, 0.9, 1.1]
        ))
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -3.0, y: -1.0, z: 0.0),
                    Point3D(x: 3.0, y: -1.0, z: 0.0),
                ],
                [
                    Point3D(x: -3.0, y: 1.0, z: 0.0),
                    Point3D(x: 3.0, y: 1.0, z: 0.0),
                ],
            ],
            weights: [[1.0, 1.2], [0.9, 1.1]]
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: CurveSurfaceIntersectionOptions(
                maximumSubdivisionDepth: 12,
                maximumIterations: 64
            ),
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        #expect(intersection.curveParameter > 0.75)
        #expect(intersection.residual <= tolerance.distance)
        #expect(intersection.kind == .transverse)
    }

    @Test(.timeLimit(.minutes(1)))
    func adaptiveBSplineBoundsRejectDisjointConvexSubcurvesBeforeSeedExhaustion() throws {
        let geometry = disjointCurveAndSurfaceWithOverlappingRootHulls()

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: geometry.curve,
            surface: geometry.surface,
            options: CurveSurfaceIntersectionOptions(
                maximumSubdivisionDepth: 8,
                maximumCandidateCount: 8
            ),
            tolerance: tolerance
        )

        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func unresolvedLeafReturnsTypedResourceFailureInsteadOfFalseEmptyResult() throws {
        let geometry = disjointCurveAndSurfaceWithOverlappingRootHulls()

        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: geometry.curve,
                surface: geometry.surface,
                options: CurveSurfaceIntersectionOptions(
                    maximumSubdivisionDepth: 0,
                    maximumSubdivisionCells: 1,
                    maximumIterations: 1,
                    maximumCandidateCount: 1
                ),
                tolerance: tolerance
            )
            Issue.record("An unresolved leaf must not be reported as an empty intersection.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual.map { $0 > tolerance.distance } == true)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplinePlanePreservesRepeatedTangentRoot() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -1.0, y: 0.0, z: 0.25),
                Point3D(x: 0.0, y: 0.0, z: -0.125),
                Point3D(x: 1.0, y: 0.0, z: 0.25),
            ],
            weights: [1.0, 2.0, 1.0]
        ))
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        #expect(intersection.kind == .tangent)
        #expect(abs(intersection.curveParameter - 0.5) <= tolerance.angle)
        #expect(intersection.point.isApproximatelyEqual(
            to: .origin,
            tolerance: tolerance.distance
        ))
        #expect(intersection.residual <= tolerance.distance)
        #expect(intersection.iterations == 0)
    }

    private func disjointCurveAndSurfaceWithOverlappingRootHulls() -> (
        curve: Curve3D,
        surface: Surface3D
    ) {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -1.0, y: 0.0, z: 1.0),
                Point3D(x: 0.0, y: 0.0, z: -0.1),
                Point3D(x: 1.0, y: 0.0, z: 1.0),
            ]
        ))
        let surface = Surface3D.bSpline(.bilinearPatch(
            bottomLeft: Point3D(x: -2.0, y: -2.0, z: 0.0),
            bottomRight: Point3D(x: 2.0, y: -2.0, z: 0.0),
            topRight: Point3D(x: 2.0, y: 2.0, z: 0.0),
            topLeft: Point3D(x: -2.0, y: 2.0, z: 0.0)
        ))
        return (curve, surface)
    }

    private func rationalVerticalPlane(x: Double) -> Surface3D {
        .bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: x, y: -2.5, z: -1.0),
                    Point3D(x: x, y: 2.5, z: -1.0),
                ],
                [
                    Point3D(x: x, y: -2.5, z: 1.0),
                    Point3D(x: x, y: 2.5, z: 1.0),
                ],
            ],
            weights: [
                [1.0, 0.8],
                [1.2, 0.9],
            ]
        ))
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineSpanCoincidentWithPlaneReturnsTypedDiagnostic() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -1.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 2.0]
        ))
        let surface = Surface3D.analytic(.plane(
            origin: .origin,
            normal: .unitZ
        ))

        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: surface,
                options: .init(),
                tolerance: tolerance
            )
            Issue.record("A coincident B-spline span must not produce discrete points.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .nonDiscreteIntersection)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func linearBSplineSpherePreservesRepeatedTangentRoot() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -2.0, y: 1.0, z: 0.0),
                Point3D(x: 2.0, y: 1.0, z: 0.0),
            ],
            weights: [1.0, 1.0]
        ))
        let surface = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 1.0
        ))

        let intersections = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance
        )

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        #expect(intersection.kind == .tangent)
        #expect(abs(intersection.curveParameter - 0.5) <= tolerance.angle)
        #expect(intersection.point.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: 1.0, z: 0.0),
            tolerance: tolerance.distance
        ))
        #expect(intersection.residual <= tolerance.distance)
        #expect(intersection.iterations == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBSplineCircleCoincidentWithSphereReturnsTypedDiagnostic() throws {
        let weight = sqrt(0.5)
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 1.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 1.0, z: 0.0),
                Point3D(x: 0.0, y: 1.0, z: 0.0),
            ],
            weights: [1.0, weight, 1.0]
        ))
        let surface = Surface3D.analytic(.sphere(
            center: .origin,
            radius: 1.0
        ))

        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: surface,
                options: .init(),
                tolerance: tolerance
            )
            Issue.record("A spherical B-spline arc must report continuous coincidence.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .nonDiscreteIntersection)
        }
    }
}

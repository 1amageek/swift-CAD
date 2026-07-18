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
}

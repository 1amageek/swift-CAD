import CADCore
import CADGeometry
import Foundation
import Testing

@Suite("B-spline Curve Analytic Surface Intersection")
struct BSplineCurveAnalyticSurfaceIntersectionTests {
    private let tolerance = ModelingTolerance(
        distance: 1.0e-9,
        angle: 1.0e-10
    )

    @Test(.timeLimit(.minutes(1)))
    func cylinderPreservesRepeatedTangentRoot() throws {
        let curve = linearCurve(
            from: Point3D(x: -2.0, y: 1.0, z: 0.0),
            to: Point3D(x: 2.0, y: 1.0, z: 0.0)
        )
        let surface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))

        let intersections = try intersections(curve: curve, surface: surface)

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        #expect(intersection.kind == .tangent)
        #expect(abs(intersection.curveParameter - 0.5) <= tolerance.angle)
        #expect(intersection.point.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: 1.0, z: 0.0),
            tolerance: tolerance.distance
        ))
        #expect(intersection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func conePreservesRepeatedTangentRoot() throws {
        let curve = linearCurve(
            from: Point3D(x: -2.0, y: 1.0, z: 1.0),
            to: Point3D(x: 2.0, y: 1.0, z: 1.0)
        )
        let surface = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi * 0.25
        ))

        let intersections = try intersections(curve: curve, surface: surface)

        let intersection = try #require(intersections.first)
        #expect(intersections.count == 1)
        #expect(intersection.kind == .tangent)
        #expect(abs(intersection.curveParameter - 0.5) <= tolerance.angle)
        #expect(intersection.point.isApproximatelyEqual(
            to: Point3D(x: 0.0, y: 1.0, z: 1.0),
            tolerance: tolerance.distance
        ))
        #expect(intersection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func torusReturnsEveryTransverseQuarticRoot() throws {
        let curve = linearCurve(
            from: Point3D(x: -5.0, y: 0.0, z: 0.0),
            to: Point3D(x: 5.0, y: 0.0, z: 0.0)
        )
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))

        let intersections = try intersections(curve: curve, surface: surface)

        #expect(intersections.count == 4)
        let expectedParameters = [0.1, 0.3, 0.7, 0.9]
        for (intersection, expectedParameter) in zip(
            intersections,
            expectedParameters
        ) {
            #expect(intersection.kind == .transverse)
            #expect(abs(intersection.curveParameter - expectedParameter) <= 1.0e-8)
            #expect(intersection.residual <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalCubicCurveFindsEveryTorusIntersectionFromDegreeTwelveImplicitPolynomial() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 3,
            knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -5.0, y: 0.0, z: 0.0),
                Point3D(x: -2.0, y: 0.0, z: 0.0),
                Point3D(x: 2.0, y: 0.0, z: 0.0),
                Point3D(x: 5.0, y: 0.0, z: 0.0),
            ],
            weights: [1.0, 0.8, 1.2, 1.0]
        ))
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))

        let result = try intersections(curve: curve, surface: surface)

        #expect(result.count == 4)
        let expectedX = [-4.0, -2.0, 2.0, 4.0]
        for (intersection, x) in zip(result, expectedX) {
            #expect(abs(intersection.point.x - x) <= tolerance.distance)
            #expect(abs(intersection.point.y) <= tolerance.distance)
            #expect(abs(intersection.point.z) <= tolerance.distance)
            #expect(intersection.kind == .transverse)
            #expect(intersection.residual <= tolerance.distance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func farAxialCylinderCurveDoesNotBecomeFalseCoincidence() throws {
        let curve = linearCurve(
            from: Point3D(x: 1.1, y: 0.0, z: 1.0e12),
            to: Point3D(x: 1.1, y: 0.0, z: 1.0e12 + 1.0)
        )
        let surface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))

        let result = try intersections(curve: curve, surface: surface)

        #expect(result.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func periodicSurfaceRangeAcceptsEquivalentSeamParameter() throws {
        let curve = linearCurve(
            from: Point3D(x: -2.0, y: 1.0, z: 0.0),
            to: Point3D(x: 2.0, y: 1.0, z: 0.0)
        )
        let surface = Surface3D.analytic(.cylinder(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        let options = CurveSurfaceIntersectionOptions(
            surfaceURange: try ScalarInterval(
                lower: 2.0 * Double.pi - 0.1,
                upper: 2.0 * Double.pi
            )
        )

        let result = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        )

        let intersection = try #require(result.first)
        #expect(result.count == 1)
        #expect(abs(intersection.surfaceU - 2.0 * Double.pi) <= tolerance.angle)
    }

    @Test(.timeLimit(.minutes(1)))
    func excludedCoincidentSpanDoesNotInvalidateBoundedQuery() throws {
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 2.0, 2.0],
            controlPoints: [
                Point3D(x: -1.0, y: 0.0, z: 0.0),
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 1.0, y: 0.0, z: 1.0),
            ]
        ))
        let surface = Surface3D.plane(Plane3D(
            origin: .origin,
            normal: .unitZ
        ))
        let options = CurveSurfaceIntersectionOptions(
            curveRange: try ScalarInterval(lower: 1.25, upper: 2.0)
        )

        let result = try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: options,
            tolerance: tolerance
        )

        #expect(result.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func coneApexReturnsTypedSingularGeometryDiagnostic() throws {
        let curve = linearCurve(
            from: Point3D(x: -1.0, y: 0.0, z: 0.0),
            to: Point3D(x: 1.0, y: 0.0, z: 0.0)
        )
        let surface = Surface3D.analytic(.cone(
            apex: .origin,
            axis: .unitZ,
            halfAngle: Double.pi * 0.25
        ))

        do {
            _ = try intersections(curve: curve, surface: surface)
            Issue.record("A cone apex intersection must report singular geometry.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularGeometry)
            #expect(error.residual == 0.0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalOuterEquatorArcIsCoincidentWithTorus() throws {
        let middleWeight = sqrt(0.5)
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 4.0, y: 0.0, z: 0.0),
                Point3D(x: 4.0, y: 4.0, z: 0.0),
                Point3D(x: 0.0, y: 4.0, z: 0.0),
            ],
            weights: [1.0, middleWeight, 1.0]
        ))
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))

        do {
            _ = try intersections(curve: curve, surface: surface)
            Issue.record("A toroidal B-spline arc must report continuous coincidence.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .nonDiscreteIntersection)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func explicitPolynomialDegreeBudgetReturnsTypedResourceDiagnostic() throws {
        let curve = linearCurve(
            from: Point3D(x: -5.0, y: 0.0, z: 0.0),
            to: Point3D(x: 5.0, y: 0.0, z: 0.0)
        )
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))
        let options = CurveSurfaceIntersectionOptions(
            maximumPolynomialDegree: 3
        )

        do {
            _ = try DefaultCurveSurfaceIntersector().intersections(
                curve: curve,
                surface: surface,
                options: options,
                tolerance: tolerance
            )
            Issue.record("The explicit polynomial budget must be enforced.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual == 4.0)
        }
    }

    private func linearCurve(from start: Point3D, to end: Point3D) -> Curve3D {
        .bSpline(BSplineCurve3D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [start, end]
        ))
    }

    private func intersections(
        curve: Curve3D,
        surface: Surface3D
    ) throws -> [CurveSurfaceIntersection] {
        try DefaultCurveSurfaceIntersector().intersections(
            curve: curve,
            surface: surface,
            options: .init(),
            tolerance: tolerance
        )
    }
}

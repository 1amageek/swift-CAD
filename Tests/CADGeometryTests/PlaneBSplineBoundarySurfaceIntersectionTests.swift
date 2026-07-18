import CADCore
@testable import CADGeometry
import Testing

@Suite("Plane B-Spline Boundary Surface Intersection")
struct PlaneBSplineBoundarySurfaceIntersectionTests {
    private let intersector = DefaultSurfaceSurfaceIntersector()
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func clampedBoundaryReturnsOriginalVerifiedRationalIsocurve() throws {
        let surface = boundarySurface()
        let plane = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let expected = try surface.uIsoparametricCurve(atV: 0.0, tolerance: tolerance)

        let intersections = try intersector.intersections(
            first: plane,
            second: .bSpline(surface),
            tolerance: tolerance
        )

        guard case let .curve(result) = try #require(intersections.first),
              case let .bSpline(curve) = result.curve else {
            Issue.record("A proven plane boundary intersection must retain its exact B-spline isocurve.")
            return
        }
        #expect(intersections.count == 1)
        #expect(curve == expected)
        #expect(curve.isRational)
        #expect(result.kind == .transverse)
        #expect(result.maximumResidual <= tolerance.distance)

        let reversed = try intersector.intersections(
            first: .bSpline(surface),
            second: plane,
            tolerance: tolerance
        )
        guard case let .curve(reversedResult) = try #require(reversed.first) else {
            Issue.record("Operand reversal must preserve the exact boundary curve.")
            return
        }
        #expect(reversedResult.curve == result.curve)
    }

    @Test(.timeLimit(.minutes(1)))
    func strictControlHullSeparationProvesEmptyIntersection() throws {
        let separated = shifted(boundarySurface(), z: 2.0)
        let intersections = try intersector.intersections(
            first: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            second: .bSpline(separated),
            tolerance: tolerance
        )
        #expect(intersections.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func repeatedPlaneLayersProduceVerifiedTangentBoundary() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 2,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
                [Point3D(x: 0.0, y: 2.0, z: 1.0), Point3D(x: 1.0, y: 2.0, z: 1.0)],
            ]
        )

        let intersections = try intersector.intersections(
            first: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            second: .bSpline(surface),
            tolerance: tolerance
        )

        guard case let .curve(result) = try #require(intersections.first) else {
            Issue.record("A repeated plane control layer must produce a tangent boundary curve.")
            return
        }
        #expect(intersections.count == 1)
        #expect(result.kind == .tangent)
        #expect(result.maximumResidual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func coincidentBoundarySpanReturnsNonDiscreteDiagnostic() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 2,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
                [Point3D(x: 0.0, y: 2.0, z: 0.0), Point3D(x: 1.0, y: 2.0, z: 0.0)],
                [Point3D(x: 0.0, y: 3.0, z: 1.0), Point3D(x: 1.0, y: 3.0, z: 1.0)],
            ]
        )

        do {
            _ = try intersector.intersections(
                first: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                second: .bSpline(surface),
                tolerance: tolerance
            )
            Issue.record("A coincident boundary span must not collapse to one curve.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .nonDiscreteIntersection)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func planarControlNetProducesCoincidence() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: 0.0), Point3D(x: 1.0, y: 0.0, z: 0.0)],
                [Point3D(x: 0.0, y: 1.0, z: 0.0), Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ]
        )
        let intersections = try intersector.intersections(
            first: .analytic(.plane(origin: .origin, normal: .unitZ)),
            second: .bSpline(surface),
            tolerance: tolerance
        )
        #expect(intersections.count == 1)
        #expect(intersections.contains {
            if case .coincident = $0 { return true }
            return false
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func interiorCrossingReturnsVerifiedCurveWithDualPcurves() throws {
        let crossing = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [Point3D(x: 0.0, y: 0.0, z: -1.0), Point3D(x: 1.0, y: 0.0, z: -1.0)],
                [Point3D(x: 0.0, y: 1.0, z: 1.0), Point3D(x: 1.0, y: 1.0, z: 1.0)],
            ]
        )

        let plane = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let intersections = try intersector.intersections(
            first: plane,
            second: .bSpline(crossing),
            tolerance: tolerance
        )

        guard case let .curve(result) = try #require(intersections.first),
              case .bSpline = result.curve else {
            Issue.record("An interior plane–B-spline section must produce a verified bounded curve.")
            return
        }
        #expect(intersections.count == 1)
        #expect(result.kind == .transverse)
        #expect(result.maximumResidual <= tolerance.distance)
        try result.firstSurfaceParameterCurve.validate(on: plane, tolerance: tolerance)
        try result.secondSurfaceParameterCurve.validate(on: .bSpline(crossing), tolerance: tolerance)

        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
            let firstParameter = try result.firstSurfaceParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let secondParameter = try result.secondSurfaceParameterCurve.parameter(
                atNormalizedFraction: fraction,
                tolerance: tolerance
            )
            let firstPoint = try plane.point(
                u: firstParameter.u,
                v: firstParameter.v,
                tolerance: tolerance
            )
            let secondPoint = try Surface3D.bSpline(crossing).point(
                u: secondParameter.u,
                v: secondParameter.v,
                tolerance: tolerance
            )
            #expect(firstPoint.isApproximatelyEqual(to: secondPoint, tolerance: tolerance.distance))
        }
    }

    private func boundarySurface() -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: -1.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: -1.0, y: 1.0, z: 1.0),
                    Point3D(x: 0.0, y: 1.0, z: 2.0),
                    Point3D(x: 1.0, y: 1.0, z: 1.0),
                ],
            ],
            weights: [
                [1.0, 0.75, 1.25],
                [1.0, 0.75, 1.25],
            ]
        )
    }

    private func shifted(_ surface: BSplineSurface3D, z: Double) -> BSplineSurface3D {
        BSplineSurface3D(
            uDegree: surface.uDegree,
            vDegree: surface.vDegree,
            uKnots: surface.uKnots,
            vKnots: surface.vKnots,
            controlPoints: surface.controlPoints.map { row in
                row.map { Point3D(x: $0.x, y: $0.y, z: $0.z + z) }
            },
            weights: surface.weights
        )
    }
}

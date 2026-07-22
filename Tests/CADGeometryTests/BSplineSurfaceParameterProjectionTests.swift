import CADCore
@testable import CADGeometry
import Testing

@Suite("B-Spline Surface Parameter Projection")
struct BSplineSurfaceParameterProjectionTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func boundedRationalSurfaceRecoversParametersWithVerifiedResidual() throws {
        let surface = try makeSurface()
        let expectedU = 0.37
        let expectedV = 0.62
        let point = try surface.point(
            u: expectedU,
            v: expectedV,
            tolerance: tolerance
        )

        let projection = try Surface3D.bSpline(surface).parameterProjection(
            of: point,
            options: SurfaceParameterProjectionOptions(
                maximumIterations: 64,
                maximumSubdivisionDepth: 24,
                maximumSubdivisionCells: 262_144,
                maximumCandidateCount: 4_096
            ),
            tolerance: tolerance
        )

        #expect(abs(projection.u - expectedU) <= tolerance.distance)
        #expect(abs(projection.v - expectedV) <= tolerance.distance)
        #expect(projection.residual <= tolerance.distance)
        #expect(projection.iterations > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func offSurfacePointReturnsTypedResidualFailure() throws {
        let surface = try makeSurface()
        let surfacePoint = try surface.point(u: 0.5, v: 0.5, tolerance: tolerance)
        let offSurfacePoint = surfacePoint + Vector3D(x: 0.0, y: 0.0, z: 1.0)

        do {
            _ = try Surface3D.bSpline(surface).parameterProjection(
                of: offSurfacePoint,
                tolerance: tolerance
            )
            Issue.record("Off-surface points must not produce an unverified UV projection.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .intersectionFailure)
            #expect(error.residual.map { $0 > tolerance.distance } == true)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func multipleDiscreteParametersReturnTypedAmbiguity() throws {
        let folded = BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                    Point3D(x: -1.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                    Point3D(x: -1.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                ],
            ]
        )
        try folded.validate(tolerance: tolerance)

        do {
            _ = try Surface3D.bSpline(folded).parameterProjection(
                of: Point3D(x: 0.25, y: 0.5, z: 0.0),
                tolerance: tolerance
            )
            Issue.record("A folded surface must not silently select one of two parameter roots.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .ambiguousSelection)
            #expect(error.residual.map { $0 <= tolerance.distance } == true)
            #expect(error.tolerance == tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func projectionSearchCoversEveryNonzeroKnotSpan() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 0.25, 0.5, 0.75, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.2),
                    Point3D(x: 2.0, y: 0.0, z: -0.1),
                    Point3D(x: 3.0, y: 0.0, z: 0.3),
                    Point3D(x: 4.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.1),
                    Point3D(x: 1.0, y: 1.0, z: 0.3),
                    Point3D(x: 2.0, y: 1.0, z: 0.0),
                    Point3D(x: 3.0, y: 1.0, z: 0.4),
                    Point3D(x: 4.0, y: 1.0, z: 0.1),
                ],
            ],
            weights: [
                [1.0, 0.8, 1.2, 0.9, 1.1],
                [1.1, 0.9, 1.0, 1.2, 0.85],
            ]
        )
        try surface.validate(tolerance: tolerance)
        let expectedU = 0.92
        let expectedV = 0.63
        let point = try surface.point(
            u: expectedU,
            v: expectedV,
            tolerance: tolerance
        )

        let projection = try Surface3D.bSpline(surface).parameterProjection(
            of: point,
            tolerance: tolerance
        )

        #expect(abs(projection.u - expectedU) <= tolerance.distance)
        #expect(abs(projection.v - expectedV) <= tolerance.distance)
        #expect(projection.residual <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonClampedNaturalDomainProjectsAndTrimsExactly() throws {
        let surface = BSplineSurface3D(
            uDegree: 2,
            vDegree: 1,
            uKnots: [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.2),
                    Point3D(x: 2.0, y: 0.0, z: -0.1),
                    Point3D(x: 3.0, y: 0.0, z: 0.1),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.2),
                    Point3D(x: 2.0, y: 1.0, z: -0.1),
                    Point3D(x: 3.0, y: 1.0, z: 0.1),
                ],
            ],
            weights: [
                [1.0, 0.8, 1.2, 1.0],
                [1.0, 0.8, 1.2, 1.0],
            ]
        )
        try surface.validate(tolerance: tolerance)
        #expect(surface.uDomain == .closed(2.0, 4.0))
        let expectedU = 3.2
        let expectedV = 0.65
        let point = try surface.point(u: expectedU, v: expectedV, tolerance: tolerance)

        let projection = try Surface3D.bSpline(surface).parameterProjection(
            of: point,
            tolerance: tolerance
        )
        #expect(abs(projection.u - expectedU) <= tolerance.distance)
        #expect(abs(projection.v - expectedV) <= tolerance.distance)
        #expect(projection.residual <= tolerance.distance)

        let naturalDomainTrim = try surface.trimmed(
            uFrom: 2.0,
            uTo: 4.0,
            vFrom: 0.0,
            vTo: 1.0,
            tolerance: tolerance
        )
        #expect(naturalDomainTrim.uKnots.prefix(3).allSatisfy { $0 == 2.0 })
        #expect(naturalDomainTrim.uKnots.suffix(3).allSatisfy { $0 == 4.0 })
        for u in [2.0, 2.4, 3.2, 3.7, 4.0] {
            let expected = try surface.point(u: u, v: expectedV, tolerance: tolerance)
            let actual = try naturalDomainTrim.point(u: u, v: expectedV, tolerance: tolerance)
            #expect(actual.isApproximatelyEqual(to: expected, tolerance: tolerance.distance))
        }

        let trimmed = try surface.trimmed(
            uFrom: 2.2,
            uTo: 3.8,
            vFrom: 0.2,
            vTo: 0.9,
            tolerance: tolerance
        )
        let trimmedPoint = try trimmed.point(
            u: expectedU,
            v: expectedV,
            tolerance: tolerance
        )
        #expect(trimmedPoint.isApproximatelyEqual(to: point, tolerance: tolerance.distance))
    }

    @Test(.timeLimit(.minutes(1)))
    func subdivisionBudgetReturnsTypedResourceFailure() throws {
        let surface = try makeSurface()
        let point = try surface.point(u: 0.37, v: 0.62, tolerance: tolerance)

        do {
            _ = try Surface3D.bSpline(surface).parameterProjection(
                of: point,
                options: SurfaceParameterProjectionOptions(
                    maximumIterations: 64,
                    maximumSubdivisionDepth: 24,
                    maximumSubdivisionCells: 1,
                    maximumCandidateCount: 1
                ),
                tolerance: tolerance
            )
            Issue.record("A bounded projection search must enforce its explicit cell budget.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .resourceLimitExceeded)
            #expect(error.residual != nil)
            #expect(error.tolerance == tolerance)
        }
    }

    private func makeSurface() throws -> BSplineSurface3D {
        let surface = BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.1),
                    Point3D(x: 2.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.5, z: -0.1),
                    Point3D(x: 1.0, y: 1.5, z: 0.4),
                    Point3D(x: 2.0, y: 1.5, z: 0.1),
                ],
                [
                    Point3D(x: 0.0, y: 3.0, z: 0.0),
                    Point3D(x: 1.0, y: 3.0, z: -0.1),
                    Point3D(x: 2.0, y: 3.0, z: 0.0),
                ],
            ],
            weights: [
                [1.0, 0.9, 1.0],
                [1.1, 0.8, 1.2],
                [1.0, 1.15, 1.0],
            ]
        )
        try surface.validate(tolerance: tolerance)
        return surface
    }
}

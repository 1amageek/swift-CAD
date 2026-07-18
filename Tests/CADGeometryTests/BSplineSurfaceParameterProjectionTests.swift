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
                seedCountPerDirection: 16,
                refinementSeedCount: 12
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

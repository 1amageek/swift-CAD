import CADCore
import CADGeometry
import Testing

@Suite("Surface Parameter Projection")
struct SurfaceParameterProjectionTests {
    @Test(.timeLimit(.minutes(1)))
    func planeProjectionRoundTripsCanonicalParameters() throws {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let point = try surface.point(u: 0.25, v: -0.75, tolerance: .standard)

        let projection = try surface.parameterProjection(of: point, tolerance: .standard)

        #expect(abs(projection.u - 0.25) <= 1.0e-12)
        #expect(abs(projection.v + 0.75) <= 1.0e-12)
        #expect(projection.residual <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func analyticSphereProjectionRoundTripsCanonicalParameters() throws {
        let surface = Surface3D.analytic(.sphere(center: .origin, radius: 2.0))
        let point = try surface.point(u: 1.25, v: 0.4, tolerance: .standard)

        let projection = try surface.parameterProjection(of: point, tolerance: .standard)

        #expect(abs(projection.u - 1.25) <= 1.0e-12)
        #expect(abs(projection.v - 0.4) <= 1.0e-12)
        #expect(projection.residual <= 1.0e-12)
    }

    @Test(.timeLimit(.minutes(1)))
    func offSurfacePointReturnsVerifiedResidualFailure() throws {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))

        do {
            _ = try surface.parameterProjection(
                of: Point3D(x: 0.0, y: 0.0, z: 1.0),
                tolerance: .standard
            )
            Issue.record("An off-surface point must not produce a valid UV projection.")
        } catch let error as KernelError {
            #expect(error.code == .intersectionFailure)
            #expect(error.residual == 1.0)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func torusAxisPointReturnsVerifiedResidualFailure() throws {
        let surface = Surface3D.analytic(.torus(
            center: .origin,
            axis: .unitZ,
            majorRadius: 3.0,
            minorRadius: 1.0
        ))

        do {
            _ = try surface.parameterProjection(
                of: Point3D(x: 0.0, y: 0.0, z: 3.5),
                tolerance: .standard
            )
            Issue.record("A ring-torus axis point must not produce a valid UV projection.")
        } catch let error as KernelError {
            #expect(error.code == .intersectionFailure)
            if let residual = error.residual {
                #expect(residual > ModelingTolerance.standard.distance)
            } else {
                Issue.record("A rejected torus projection must report its verified residual.")
            }
        }
    }
}

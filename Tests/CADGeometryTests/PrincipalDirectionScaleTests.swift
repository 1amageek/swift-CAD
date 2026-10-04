import CADCore
import CADGeometry
import Testing

@Suite("B-spline principal direction scale")
struct PrincipalDirectionScaleTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func smallMetreNonUmbilicSurfaceKeepsPrincipalAxesAcrossRescaling() throws {
        let firstCurvature = 0.2
        let secondCurvature = 0.4
        let curvatureGap = secondCurvature - firstCurvature
        let fixedFloor = tolerance.relative * 64.0
        var reference: (minimum: Vector3D, maximum: Vector3D)?

        for scale in [1.0e-5, 1.0e-4] {
            // These are the exact scale conditions that made the old unit floors reject the
            // candidate: the curvature gap remains non-umbilic while the candidate is below the
            // fixed floor. The scale-aware implementation must still produce both axes.
            #expect(curvatureGap / scale > fixedFloor)
            #expect(scale * scale * curvatureGap < fixedFloor)

            let geometry = try paraboloid(
                scale: scale,
                firstCurvature: firstCurvature,
                secondCurvature: secondCurvature
            ).differentialGeometry(
                u: 0.5,
                v: 0.5,
                tolerance: tolerance
            )
            let positionTolerance = scale * 1.0e-10
            let expectedCenterZ = 0.0
            #expect(abs(geometry.position.x) <= positionTolerance)
            #expect(abs(geometry.position.y) <= positionTolerance)
            #expect(abs(geometry.position.z - expectedCenterZ) <= positionTolerance)
            #expect(abs(geometry.tangentU.x - scale) <= positionTolerance)
            #expect(abs(geometry.tangentU.y) <= positionTolerance)
            #expect(abs(geometry.tangentU.z) <= positionTolerance)
            #expect(abs(geometry.tangentV.x) <= positionTolerance)
            #expect(abs(geometry.tangentV.y - scale) <= positionTolerance)
            #expect(abs(geometry.tangentV.z) <= positionTolerance)
            #expect(abs(geometry.normal.z - 1.0) <= 1.0e-10)
            #expect(abs(geometry.normalCurvatureU - firstCurvature / scale) <= firstCurvature / scale * 1.0e-10)
            #expect(abs(geometry.normalCurvatureV - secondCurvature / scale) <= secondCurvature / scale * 1.0e-10)
            #expect(geometry.minimumPrincipalDirection.length.isFinite)
            #expect(abs(geometry.minimumPrincipalDirection.length - 1.0) <= 1.0e-12)
            #expect(abs(geometry.maximumPrincipalDirection.length - 1.0) <= 1.0e-12)
            #expect(abs(geometry.minimumPrincipalDirection.x) >= 1.0 - 1.0e-10)
            #expect(abs(geometry.minimumPrincipalDirection.y) <= 1.0e-10)
            #expect(abs(geometry.maximumPrincipalDirection.x) <= 1.0e-10)
            #expect(abs(geometry.maximumPrincipalDirection.y) >= 1.0 - 1.0e-10)
            #expect(abs(geometry.minimumPrincipalDirection.dot(geometry.maximumPrincipalDirection)) <= 1.0e-10)

            if let reference {
                #expect(abs(reference.minimum.dot(geometry.minimumPrincipalDirection)) >= 1.0 - 1.0e-10)
                #expect(abs(reference.maximum.dot(geometry.maximumPrincipalDirection)) >= 1.0 - 1.0e-10)
            } else {
                reference = (
                    geometry.minimumPrincipalDirection,
                    geometry.maximumPrincipalDirection
                )
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func nearUmbilicSurfaceRetainsOriginalOrthonormalTangentFallback() throws {
        let geometry = try paraboloid(
            scale: 1.0e-4,
            firstCurvature: 0.2,
            secondCurvature: 0.2
        ).differentialGeometry(u: 0.5, v: 0.5, tolerance: tolerance)

        #expect(abs(geometry.minimumPrincipalCurvature - geometry.maximumPrincipalCurvature) <= 1.0e-12)
        #expect(abs(geometry.minimumPrincipalDirection.x) >= 1.0 - 1.0e-10)
        #expect(abs(geometry.minimumPrincipalDirection.y) <= 1.0e-10)
        #expect(abs(geometry.maximumPrincipalDirection.x) <= 1.0e-10)
        #expect(abs(geometry.maximumPrincipalDirection.y) >= 1.0 - 1.0e-10)
        #expect(abs(geometry.minimumPrincipalDirection.dot(geometry.maximumPrincipalDirection)) <= 1.0e-10)
    }

    @Test(.timeLimit(.minutes(1)))
    func collapsedSurfaceReportsTypedSingularFailure() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [.origin, .origin],
                [.origin, .origin],
            ]
        )

        do {
            _ = try surface.differentialGeometry(u: 0.5, v: 0.5, tolerance: tolerance)
            Issue.record("A collapsed surface must not return fabricated principal directions.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularSystem)
            #expect(error.tolerance == tolerance)
        }
    }

    private func paraboloid(
        scale: Double,
        firstCurvature: Double,
        secondCurvature: Double
    ) -> BSplineSurface3D {
        // These are the degree-two Bernstein coefficients of the centered polynomial
        // S(u,v) = (scale * (u - 0.5), scale * (v - 0.5),
        // scale / 2 * (k1 * (u - 0.5)^2 + k2 * (v - 0.5)^2)).
        let axis = [-0.5, 0.0, 0.5]
        let square = [0.25, -0.25, 0.25]
        let points = axis.indices.map { vIndex in
            axis.indices.map { uIndex in
                Point3D(
                    x: scale * axis[uIndex],
                    y: scale * axis[vIndex],
                    z: scale * 0.5 * (
                        firstCurvature * square[uIndex]
                            + secondCurvature * square[vIndex]
                    )
                )
            }
        }
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: points
        )
    }
}

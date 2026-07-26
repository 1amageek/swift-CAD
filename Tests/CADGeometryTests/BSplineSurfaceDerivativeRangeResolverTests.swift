import Testing
@testable import CADGeometry
import CADCore

@Suite("B-spline Surface Derivative Range Resolver")
struct BSplineSurfaceDerivativeRangeResolverTests {
    private let tolerance = ModelingTolerance.standard

    @Test
    func rationalCylinderDerivativesRemainInsideCertifiedRanges() throws {
        let canonical = CanonicalAnalyticSurface.cylinder(.init(
            origin: .origin,
            axis: .unitZ,
            radius: 1.0
        ))
        let surface = try AnalyticSurfaceBSplineBuilder().surface(
            for: canonical,
            boundedByPoints: [
                Point3D(x: -1.0, y: -1.0, z: -0.1),
                Point3D(x: 1.0, y: 1.0, z: 0.1),
            ],
            periodicSeamOffset: Double.pi * 0.125,
            tolerance: tolerance
        )
        let trimmed = try surface.trimmed(
            uFrom: 3.25,
            uTo: 3.75,
            vFrom: -0.05,
            vTo: 0.05,
            tolerance: tolerance
        )
        let ranges = try DefaultBSplineSurfaceDerivativeRangeResolver()
            .derivativeRanges(
                surface: trimmed,
                tolerance: tolerance
            )

        for u in [3.25, 3.5, 3.75] {
            for v in [-0.05, 0.0, 0.05] {
                let differential = try Surface3D.bSpline(trimmed)
                    .differentialGeometry(
                        atU: u,
                        v: v,
                        tolerance: tolerance
                    )
                assertContains(differential.tangentU.x, in: ranges.u.x)
                assertContains(differential.tangentU.y, in: ranges.u.y)
                assertContains(differential.tangentU.z, in: ranges.u.z)
                assertContains(differential.tangentV.x, in: ranges.v.x)
                assertContains(differential.tangentV.y, in: ranges.v.y)
                assertContains(differential.tangentV.z, in: ranges.v.z)
            }
        }
    }

    private func assertContains(
        _ value: Double,
        in interval: ScalarInterval
    ) {
        #expect(value >= interval.lower)
        #expect(value <= interval.upper)
    }
}

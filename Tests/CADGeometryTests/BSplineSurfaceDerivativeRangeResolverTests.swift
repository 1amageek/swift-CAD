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
        var execution = try OriginalQueryExecution.independentGeometry()
        let prepared = try PreparedBSplineSurfaceDifferentialEncloser(
            surface: trimmed, tolerance: tolerance, using: &execution)
        let ranges = try prepared.intervalJet(overClosedBox: SurfaceParameterBox(
            u: try ScalarInterval(lower: 3.25, upper: 3.75),
            v: try ScalarInterval(lower: -0.05, upper: 0.05)),
            tolerance: tolerance, using: &execution)

        for u in [3.25, 3.5, 3.75] {
            for v in [-0.05, 0.0, 0.05] {
                let differential = try Surface3D.bSpline(trimmed)
                    .differentialGeometry(
                        u: u,
                        v: v,
                        tolerance: tolerance
                    )
                assertContains(differential.tangentU.x, in: ranges.x.derivativeU)
                assertContains(differential.tangentU.y, in: ranges.y.derivativeU)
                assertContains(differential.tangentU.z, in: ranges.z.derivativeU)
                assertContains(differential.tangentV.x, in: ranges.x.derivativeV)
                assertContains(differential.tangentV.y, in: ranges.y.derivativeV)
                assertContains(differential.tangentV.z, in: ranges.z.derivativeV)
            }
        }
    }

    private func assertContains(
        _ value: Double,
        in interval: OutwardScalarInterval
    ) {
        #expect(value >= interval.lower)
        #expect(value <= interval.upper)
    }
}

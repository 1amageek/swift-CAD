import Testing
import CADCore
@testable import CADGeometry

@Suite("Exact rational Coons surface")
struct ExactCoonsBSplineSurfaceBuilderTests {
    @Test(.timeLimit(.minutes(1)))
    func rationalMixedDegreeAndMultiSpanBoundariesAreInterpolatedExactly() throws {
        let boundaries = planarRationalBoundaries()
        let surface = try ExactCoonsBSplineSurfaceBuilder().build(
            vMinimumBoundary: boundaries.vMinimum,
            vMaximumBoundary: boundaries.vMaximum,
            uMinimumBoundary: boundaries.uMinimum,
            uMaximumBoundary: boundaries.uMaximum,
            tolerance: .standard
        )

        try surface.validate(tolerance: .standard)
        #expect(surface.uDegree == 5)
        #expect(surface.vDegree == 5)
        #expect(surface.isRational)
        #expect(surface.weights.flatMap { $0 }.allSatisfy { $0 > 0.0 })
        for index in 0...32 {
            let fraction = Double(index) / 32.0
            let residuals = [
                try (surface.point(u: fraction, v: 0.0, tolerance: .standard)
                    - boundaries.vMinimum.point(at: fraction, tolerance: .standard)).length,
                try (surface.point(u: fraction, v: 1.0, tolerance: .standard)
                    - boundaries.vMaximum.point(at: 2.0 + 3.0 * fraction, tolerance: .standard)).length,
                try (surface.point(u: 0.0, v: fraction, tolerance: .standard)
                    - boundaries.uMinimum.point(at: fraction, tolerance: .standard)).length,
                try (surface.point(u: 1.0, v: fraction, tolerance: .standard)
                    - boundaries.uMaximum.point(at: -1.0 + 2.0 * fraction, tolerance: .standard)).length,
            ]
            #expect((residuals.max() ?? .infinity) <= ModelingTolerance.standard.distance)
        }
        try BSplineSurfaceRegularityValidator().validate(
            surface,
            uDomain: surface.uDomain,
            vDomain: surface.vDomain,
            tolerance: .standard
        )
        try BSplineSurfaceEmbeddingValidator().validate(
            surface,
            uDomain: surface.uDomain,
            vDomain: surface.vDomain,
            tolerance: .standard
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func nonMeetingBoundariesReturnTypedInvalidInput() throws {
        var boundaries = planarRationalBoundaries()
        boundaries.uMaximum.controlPoints[0].z = 1.0

        do {
            _ = try ExactCoonsBSplineSurfaceBuilder().build(
                vMinimumBoundary: boundaries.vMinimum,
                vMaximumBoundary: boundaries.vMaximum,
                uMinimumBoundary: boundaries.uMinimum,
                uMaximumBoundary: boundaries.uMaximum,
                tolerance: .standard
            )
            Issue.record("Non-meeting Coons boundaries must not produce a surface.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .invalidInput)
            #expect(error.tolerance == .standard)
        }
    }

    private struct Boundaries {
        var vMinimum: BSplineCurve3D
        var vMaximum: BSplineCurve3D
        var uMinimum: BSplineCurve3D
        var uMaximum: BSplineCurve3D
    }

    private func planarRationalBoundaries() -> Boundaries {
        Boundaries(
            vMinimum: BSplineCurve3D(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                    Point3D(x: 2.0, y: 0.0, z: 0.0),
                ],
                weights: [1.0, 0.7, 1.0]
            ),
            vMaximum: BSplineCurve3D(
                degree: 1,
                knots: [2.0, 2.0, 3.0, 5.0, 5.0],
                controlPoints: [
                    Point3D(x: 0.0, y: 2.0, z: 0.0),
                    Point3D(x: 0.6, y: 2.0, z: 0.0),
                    Point3D(x: 2.0, y: 2.0, z: 0.0),
                ],
                weights: [1.0, 0.8, 1.0]
            ),
            uMinimum: BSplineCurve3D(
                degree: 1,
                knots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 0.0, y: 2.0, z: 0.0),
                ]
            ),
            uMaximum: BSplineCurve3D(
                degree: 2,
                knots: [-1.0, -1.0, -1.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 2.0, y: 0.0, z: 0.0),
                    Point3D(x: 2.0, y: 1.0, z: 0.0),
                    Point3D(x: 2.0, y: 2.0, z: 0.0),
                ],
                weights: [1.0, 0.65, 1.0]
            )
        )
    }
}

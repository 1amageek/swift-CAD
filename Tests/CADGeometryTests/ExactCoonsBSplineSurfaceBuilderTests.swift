import Testing
import CADCore
@testable import CADGeometry

@Suite("Exact rational Coons surface")
struct ExactCoonsBSplineSurfaceBuilderTests {
    @Test func polynomialCommonBasisRetainsDegreeAndCoonsInterior() throws {
        var b = planarRationalBoundaries()
        b.vMinimum.weights = [1, 1, 1]
        b.vMaximum.weights = [1, 1, 1]
        b.uMaximum.weights = [1, 1, 1]
        b.vMinimum.controlPoints[1].z = 0.4
        b.uMaximum.controlPoints[1].z = -0.3
        let builder = ExactCoonsBSplineSurfaceBuilder(maximumPatchCount: 2, maximumResultDegree: 2)
        let surface = try builder.build(vMinimumBoundary: b.vMinimum, vMaximumBoundary: b.vMaximum,
            uMinimumBoundary: b.uMinimum, uMaximumBoundary: b.uMaximum, tolerance: .standard)
        #expect(surface.uDegree == 2 && surface.vDegree == 2)
        #expect(surface.weights.allSatisfy { $0.allSatisfy { $0 == 1 } })
        for i in 0...8 {
            for j in 0...8 {
                let u = Double(i) / 8, v = Double(j) / 8
                let bottom = try b.vMinimum.point(at: u, tolerance: .standard)
                let top = try b.vMaximum.point(at: 2 + 3 * u, tolerance: .standard)
                let left = try b.uMinimum.point(at: v, tolerance: .standard)
                let right = try b.uMaximum.point(at: -1 + 2 * v, tolerance: .standard)
                let expected = bottom + (top - bottom) * v
                    + (left + (right - left) * u - Point3D(x: 2 * u, y: 2 * v, z: 0))
                #expect(try (surface.point(u: u, v: v, tolerance: .standard) - expected).length
                    <= ModelingTolerance.standard.distance)
            }
        }
        for limits in [(1, 2), (2, 1)] {
            do {
                _ = try ExactCoonsBSplineSurfaceBuilder(maximumPatchCount: limits.0,
                    maximumResultDegree: limits.1).build(vMinimumBoundary: b.vMinimum,
                    vMaximumBoundary: b.vMaximum, uMinimumBoundary: b.uMinimum,
                    uMaximumBoundary: b.uMaximum, tolerance: .standard)
                Issue.record("Polynomial specialization must preserve resource limits.")
            } catch let error as KernelError {
                #expect(error.code == .resourceLimitExceeded)
            }
        }
    }

    @Test func nearUnitWeightsRemainRational() throws {
        var b = planarRationalBoundaries()
        b.vMinimum.weights = [1, 1 + 5e-13, 1]
        b.vMaximum.weights = [1, 1, 1]
        b.uMaximum.weights = [1, 1, 1]
        b.vMinimum.controlPoints[1].z = 1e9
        let surface = try ExactCoonsBSplineSurfaceBuilder().build(vMinimumBoundary: b.vMinimum,
            vMaximumBoundary: b.vMaximum, uMinimumBoundary: b.uMinimum,
            uMaximumBoundary: b.uMaximum, tolerance: .standard)
        #expect(surface.uDegree == 5 && surface.vDegree == 5)
        let actual = try surface.point(u: 0.5, v: 0, tolerance: .standard)
        let expected = try b.vMinimum.point(at: 0.5, tolerance: .standard)
        #expect((actual - expected).length < 1e-6)
        #expect(abs(actual.z - 5e8) > 1e-5)
    }

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

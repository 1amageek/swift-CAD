import Testing
import CADCore
@testable import CADGeometry

@Suite("B-spline surface embedding certification")
struct BSplineSurfaceEmbeddingValidatorTests {
    @Test(.timeLimit(.minutes(1)))
    func rationalBezierGraphsCertifyWithoutSubdivision() throws {
        let validator = BSplineSurfaceEmbeddingValidator(
            maximumLocalSubdivisionDepth: 0,
            maximumCellCount: 1,
            maximumPairSubdivisionDepth: 0,
            maximumPairCellCount: 1
        )

        for surface in [rationalPlanarPatch(), rationalSpatialPatch()] {
            try validator.validate(
                surface,
                uDomain: surface.uDomain,
                vDomain: surface.vDomain,
                tolerance: .standard
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rationalBezierGraphsCertifyRegularityWithoutSubdivision() throws {
        let validator = BSplineSurfaceRegularityValidator(
            maximumSubdivisionDepth: 0,
            maximumCellCount: 1
        )

        for surface in [rationalPlanarPatch(), rationalSpatialPatch()] {
            try validator.validate(
                surface,
                uDomain: surface.uDomain,
                vDomain: surface.vDomain,
                tolerance: .standard
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func foldedBilinearPatchIsRejectedAsSingular() throws {
        let surface = BSplineSurface3D.bilinearPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 1.0, y: 1.0, z: 0.0),
            topRight: Point3D(x: 0.0, y: 1.0, z: 0.0),
            topLeft: Point3D(x: 1.0, y: 0.0, z: 0.0)
        )

        do {
            try BSplineSurfaceEmbeddingValidator().validate(
                surface,
                uDomain: surface.uDomain,
                vDomain: surface.vDomain,
                tolerance: .standard
            )
            Issue.record("A folded B-spline surface must not certify as embedded.")
        } catch let error as KernelError {
            #expect(error.phase == .geometry)
            #expect(error.code == .singularGeometry)
        }
    }

    private func rationalPlanarPatch() -> BSplineSurface3D {
        let base = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.0, z: 0.0),
            bottomRight: Point3D(x: 0.02, y: 0.0, z: 0.0),
            topRight: Point3D(x: 0.02, y: 0.02, z: 0.0),
            topLeft: Point3D(x: 0.0, y: 0.02, z: 0.0)
        )
        var weights = base.weights
        weights[1][1] = 2.0
        return BSplineSurface3D(
            uDegree: base.uDegree,
            vDegree: base.vDegree,
            uKnots: base.uKnots,
            vKnots: base.vKnots,
            controlPoints: base.controlPoints,
            weights: weights
        )
    }

    private func rationalSpatialPatch() -> BSplineSurface3D {
        let base = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: Point3D(x: 0.0, y: 0.04, z: 0.004),
            bottomRight: Point3D(x: 0.02, y: 0.04, z: -0.002),
            topRight: Point3D(x: 0.02, y: 0.06, z: 0.003),
            topLeft: Point3D(x: 0.0, y: 0.06, z: 0.001)
        )
        var weights = base.weights
        weights[0][1] = 1.2
        weights[1][1] = 1.4
        weights[2][1] = 1.6
        return BSplineSurface3D(
            uDegree: base.uDegree,
            vDegree: base.vDegree,
            uKnots: base.uKnots,
            vKnots: [0.0, 0.0, 0.0, 0.0, 2.0, 2.0, 2.0, 2.0],
            controlPoints: base.controlPoints,
            weights: weights
        )
    }
}

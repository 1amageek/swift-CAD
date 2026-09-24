import Testing
import CADCore
@testable import CADGeometry

@Suite("B-spline surface embedding certification")
struct BSplineSurfaceEmbeddingValidatorTests {
    @Test(arguments: [[0.0, 0.0, 1.0, 1.0], [0.0, 0.0, 0.0, 1.0], [0.0, 1.0, 1.0, 1.0]])
    func stationaryOuterParametersRetainARegularEmbeddedSheet(coordinates: [Double]) throws {
        let surface = BSplineSurface3D(uDegree: 3, vDegree: 3,
            uKnots: [0, 0, 0, 0, 1, 1, 1, 1], vKnots: [0, 0, 0, 0, 1, 1, 1, 1],
            controlPoints: coordinates.map { y in coordinates.map { x in Point3D(x: x, y: y, z: x + y) } })
        let regularity = BSplineSurfaceRegularityValidator(maximumSubdivisionDepth: 0, maximumCellCount: 1)
        let embedding = BSplineSurfaceEmbeddingValidator(maximumLocalSubdivisionDepth: 0, maximumCellCount: 1)
        #expect(throws: (any Error).self) {
            try regularity.validate(surface, uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: .standard)
        }
        #expect(throws: (any Error).self) {
            try embedding.validate(surface, uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: .standard)
        }
        try regularity.validate(surface, uDomain: surface.uDomain, vDomain: surface.vDomain,
            tolerance: .standard, allowStationaryBoundaryParameterization: true)
        try embedding.validate(surface, uDomain: surface.uDomain, vDomain: surface.vDomain,
            tolerance: .standard, allowStationaryBoundaryParameterization: true)
    }

    @Test(arguments: [0, 1, 2, 3])
    func stationaryBoundaryAdmissionCannotHideInteriorOrCollapsedGeometry(kind: Int) throws {
        let x: [Double] = kind == 3 ? [0, 0, 0, 0] : (kind == 0 ? [0, 1, 0, 1] : [0, 2, -1, 1])
        let points = kind == 2
            ? [Array(repeating: Point3D.origin, count: 4), x.map { Point3D(x: $0, y: 1, z: 0) }]
            : [0.0, 1.0].map { y in x.map { Point3D(x: $0, y: y, z: 0) } }
        let surface = BSplineSurface3D(uDegree: 3, vDegree: 1,
            uKnots: [0, 0, 0, 0, 1, 1, 1, 1], vKnots: [0, 0, 1, 1], controlPoints: points)
        #expect(throws: (any Error).self) {
            try BSplineSurfaceRegularityValidator(maximumSubdivisionDepth: 0).validate(surface,
                uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: .standard,
                allowStationaryBoundaryParameterization: true)
        }
        #expect(throws: (any Error).self) {
            try BSplineSurfaceEmbeddingValidator(maximumLocalSubdivisionDepth: 0).validate(surface,
                uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: .standard,
                allowStationaryBoundaryParameterization: true)
        }
    }

    @Test func coarseSeparationRetainsTheRequestPairBudget() throws {
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 2, 3, 4, 4], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 1.0].map { y in
                (0...4).map { Point3D(x: Double($0), y: y, z: 0) }
            })
        try BSplineSurfaceEmbeddingValidator(maximumLocalSubdivisionDepth: 0,
            maximumCellCount: 4, maximumPairSubdivisionDepth: 0, maximumPairCellCount: 3)
            .validate(surface, uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: .standard)
        do {
            try BSplineSurfaceEmbeddingValidator(maximumLocalSubdivisionDepth: 0,
                maximumCellCount: 4, maximumPairSubdivisionDepth: 0, maximumPairCellCount: 2)
                .validate(surface, uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: .standard)
            Issue.record("The third nonadjacent pair must consume the shared proof budget.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test func locallyRegularCrossingStripsFailGlobalSeparation() throws {
        let path = [Point3D(x: 0, y: 0, z: 0), Point3D(x: 1, y: 1, z: 0),
            Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 0, z: 0)]
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 2, 3, 3], vKnots: [0, 0, 1, 1],
            controlPoints: [path, path.map { $0 + Vector3D(x: 0, y: 0, z: 1) }])
        do {
            try BSplineSurfaceEmbeddingValidator().validate(surface,
                uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: .standard)
            Issue.record("A local regularity certificate cannot admit crossing nonadjacent strips.")
        } catch let error as KernelError {
            #expect(error.code == .singularGeometry)
        }
    }

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

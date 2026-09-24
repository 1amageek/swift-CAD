import Testing
import CADCore
@testable import CADGeometry

@Suite("B-spline surface embedding certification")
struct BSplineSurfaceEmbeddingValidatorTests {
    @Test(arguments: [false, true], [false, true])
    func oppositeSharedBoundariesStillRequireInteriorSeparation(reversed: Bool, rational: Bool) throws {
        func strip(_ height: Double) -> BSplineSurface3D {
            let rows = [0.0, 1.0].map { z in
                [Point3D(x: -1, y: 0, z: z), Point3D(x: 0, y: height, z: z), Point3D(x: 1, y: 0, z: z)]
            }
            return BSplineSurface3D(uDegree: 2, vDegree: 1,
                uKnots: [0, 0, 0, 1, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: reversed ? rows.map { Array($0.reversed()) } : rows,
                weights: Array(repeating: rational ? [1, 0.7, 1] : [1, 1, 1], count: 2))
        }
        let sides: [SurfaceParameterBoundary] = [.uLower, .uUpper]
        let validator = BSplineSurfaceEmbeddingValidator()
        try validator.validateOppositeBoundaryContacts(first: strip(1), firstBoundaries: sides,
            second: strip(-1), secondBoundaries: sides, tolerance: .standard)
        #expect(throws: KernelError.self) {
            try validator.validateOppositeBoundaryContacts(first: strip(1), firstBoundaries: sides,
                second: strip(1), secondBoundaries: sides, tolerance: .standard)
        }
    }

    @Test(arguments: [false, true])
    func multipleCornerContactsDoNotAuthorizeAnEntireSharedEdge(rational: Bool) throws {
        let weights = rational ? [[1.0, 0.7], [1.3, 1]] : [[1, 1], [1, 1]]
        func surface(_ heights: [[Double]]) -> BSplineSurface3D {
            BSplineSurface3D(uDegree: 1, vDegree: 1,
                uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: (0..<2).map { v in (0..<2).map { u in
                    Point3D(x: Double(u), y: Double(v), z: heights[v][u])
                } }, weights: weights)
        }
        let first = surface([[0, 0], [0, 0]])
        let zero = Point2D(x: 0, y: 0), one = Point2D(x: 1, y: 1)
        let validator = BSplineSurfaceEmbeddingValidator(maximumPairSubdivisionDepth: 16, maximumPairCellCount: 4096)
        try validator.validateSeparation(first: first, second: surface([[0, 1], [1, 0]]),
            tolerance: .standard, allowedCornerContacts: [(zero, zero), (one, one)])
        let edgeEnd = Point2D(x: 1, y: 0)
        #expect(throws: KernelError.self) {
            try validator.validateSeparation(first: first, second: surface([[0, 0], [1, 1]]),
                tolerance: .standard, allowedCornerContacts: [(zero, zero), (edgeEnd, edgeEnd)])
        }
        #expect(throws: KernelError.self) {
            try validator.validateSeparation(first: first, second: first, tolerance: .standard,
                allowedCornerContacts: [(zero, zero), (zero, zero)])
        }
    }

    @Test(arguments: [false, true])
    func permittedCornerDoesNotExemptOtherSurfaceContacts(rational: Bool) throws {
        func square(_ lower: Double, _ upper: Double) -> BSplineSurface3D {
            BSplineSurface3D(uDegree: 1, vDegree: 1,
                uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: [lower, upper].map { y in
                    [lower, upper].map { x in Point3D(x: x, y: y, z: 0) }
                }, weights: rational ? [[1, 0.7], [1.3, 1]] : [[1, 1], [1, 1]])
        }
        let first = square(-1, 0), second = square(0, 1)
        let zero = Point2D(x: 0, y: 0)
        let validator = BSplineSurfaceEmbeddingValidator(maximumPairSubdivisionDepth: 8, maximumPairCellCount: 1024)
        try validator.validateSeparation(first: first, second: second, tolerance: .standard,
            allowedCornerContacts: [(Point2D(x: 1, y: 1), zero)])
        try validator.validateSeparation(first: second, second: first, tolerance: .standard,
            allowedCornerContacts: [(zero, Point2D(x: 1, y: 1))])
        #expect(throws: KernelError.self) {
            try validator.validateSeparation(first: first, second: square(0, -0.5), tolerance: .standard,
                allowedCornerContacts: [(Point2D(x: 1, y: 1), zero)])
        }
        #expect(throws: KernelError.self) {
            try validator.validateSeparation(first: first, second: second, tolerance: .standard,
                allowedCornerContacts: [(zero, zero)])
        }
    }

    @Test func polynomialInteriorBoundsDoNotDependOnBoundaryRequests() {
        let patch = RationalBezierSurfacePatch3D(
            controlPoints: [[.origin, Point3D(x: 2, y: 0, z: 0)],
                            [Point3D(x: 0, y: 3, z: 0), Point3D(x: 2, y: 3, z: 6)]],
            weights: [[1, 1], [1, 1]], uLower: 0, uUpper: 2, vLower: 0, vUpper: 3)
        let interior = RationalBezierSurfaceDifferentialBounds(patch: patch)
        let boundary = RationalBezierSurfaceDifferentialBounds(patch: patch,
            stationaryBoundaries: Set(SurfaceParameterBoundary.allCases))
        for (a, b) in [(interior.tangentUNumerator, boundary.tangentUNumerator),
                       (interior.tangentVNumerator, boundary.tangentVNumerator),
                       (interior.normalNumerator, boundary.normalNumerator)] {
            for (x, y) in [(a.x, b.x), (a.y, b.y), (a.z, b.z)] {
                #expect(x.lower == y.lower && x.upper == y.upper)
            }
        }
        // S(u,v) = (u,v,u*v), hence Su x Sv = (-v,-u,1).
        #expect(interior.normalNumerator.x.lower <= -3)
        #expect(interior.normalNumerator.x.upper >= 0)
        #expect(interior.normalNumerator.y.lower <= -2)
        #expect(interior.normalNumerator.y.upper >= 0)
        #expect(interior.normalNumerator.z.lower <= 1)
        #expect(interior.normalNumerator.z.upper >= 1)
        #expect(interior.normalNumerator.z.lower > 0)
    }

    @Test
    func curvedCommonSeamRefinesCoarseNeighborsBeforeFineCells() throws {
        let seam = [Point3D(x: 0.002, y: -0.001, z: 0), Point3D(x: 0.005, y: -0.001, z: 0.0025),
            Point3D(x: 0.005, y: -0.001, z: 0.0075), Point3D(x: 0.002, y: -0.001, z: 0.01)]
        let heights = [0.0, 0.01 / 3, 0.02 / 3, 0.01]
        let first = BSplineSurface3D(uDegree: 3, vDegree: 1,
            uKnots: [0, 0, 0, 0, 1, 1, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [heights.map { Point3D(x: 0.002, y: 0.001, z: $0) }, seam])
        let second = BSplineSurface3D(uDegree: 3, vDegree: 1,
            uKnots: first.uKnots, vKnots: first.vKnots,
            controlPoints: [seam, heights.map { Point3D(x: -0.002, y: -0.001, z: $0) }])
        try BSplineSurfaceEmbeddingValidator().validateAdjacent(first: first, firstBoundary: .vUpper,
            second: second, secondBoundary: .vLower, tolerance: .standard)
    }
    @Test(arguments: [false, true], [false, true])
    func differentDegreeStraightSeamsRequireGeometricAdjacency(reversed: Bool, rational: Bool) throws {
        let first = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 1.0].map { y in
                [0.0, 1.0].map { x in Point3D(x: x, y: y, z: 0) }
            })
        func second(outerX: Double) -> BSplineSurface3D {
            let ordinates = [0.0, 1.0 / 3, 2.0 / 3, 1.0]
            let weights = rational ? [1.0, 0.7, 1.3, 1.0] : [1, 1, 1, 1]
            return BSplineSurface3D(uDegree: 1, vDegree: 3,
                uKnots: [0, 0, 1, 1], vKnots: [0, 0, 0, 0, 1, 1, 1, 1],
                controlPoints: (reversed ? Array(ordinates.reversed()) : ordinates).map { y in
                    [1.0, outerX].map { x in Point3D(x: x, y: y, z: 0) }
                }, weights: weights.map { [$0, $0] })
        }
        try BSplineSurfaceEmbeddingValidator().validateAdjacent(first: first, firstBoundary: .uUpper,
            second: second(outerX: 2), secondBoundary: .uLower, tolerance: .standard)
        #expect(throws: KernelError.self) {
            try BSplineSurfaceEmbeddingValidator().validateAdjacent(first: first, firstBoundary: .uUpper,
                second: second(outerX: 0.5), secondBoundary: .uLower, tolerance: .standard)
        }
    }
    @Test(arguments: SurfaceParameterBoundary.allCases, [false, true])
    func adjacentChartsUseTheirActualParameterSide(boundary: SurfaceParameterBoundary, reversed: Bool) throws {
        let knots = [0.0, 0, 1, 1]
        let first = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: knots,
            controlPoints: [[.origin, Point3D(x: 1, y: 0, z: 0)],
                            [Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)]])
        var points = [[Point3D(x: 0, y: 1, z: 0), Point3D(x: 1, y: 1, z: 0)],
                      [Point3D(x: 0, y: 1, z: 1), Point3D(x: 1, y: 1, z: 1)]]
        if reversed { points = points.map { Array($0.reversed()) } }
        if boundary == .vUpper || boundary == .uUpper { points.reverse() }
        if boundary == .uLower || boundary == .uUpper {
            points = points[0].indices.map { i in points.map { $0[i] } }
        }
        let second = BSplineSurface3D(uDegree: 1, vDegree: 1, uKnots: knots, vKnots: knots,
            controlPoints: points)
        try BSplineSurfaceEmbeddingValidator().validateAdjacent(first: first, firstBoundary: .vUpper,
            second: second, secondBoundary: boundary, tolerance: .standard)
        try BSplineSurfaceEmbeddingValidator().validateAdjacent(first: second, firstBoundary: boundary,
            second: first, secondBoundary: .vUpper, tolerance: .standard)
    }

    @Test func adjacencyDoesNotSnapASeamOrAcceptFoldback() throws {
        func strip(_ lower: Double, _ upper: Double) -> BSplineSurface3D {
            BSplineSurface3D(uDegree: 1, vDegree: 1,
                uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: [lower, upper].map { y in
                    [Point3D(x: 0, y: y, z: 0), Point3D(x: 1, y: y, z: 0)]
                })
        }
        let first = strip(0, 1)
        try BSplineSurfaceEmbeddingValidator().validateAdjacent(first: first, firstBoundary: .vUpper,
            second: strip(1, 2), secondBoundary: .vLower, tolerance: .standard)
        for second in [strip(1, 0.5), strip(1.nextUp, 2)] {
            #expect(throws: KernelError.self) {
                try BSplineSurfaceEmbeddingValidator().validateAdjacent(first: first, firstBoundary: .vUpper,
                    second: second, secondBoundary: .vLower, tolerance: .standard)
            }
        }
        #expect(throws: KernelError.self) {
            try BSplineSurfaceEmbeddingValidator(maximumCellCount: 1)
                .validateAdjacent(first: first, firstBoundary: .vUpper,
                    second: strip(1, 2), secondBoundary: .vLower, tolerance: .standard)
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [1.0, 1.7])
    func differentSurfaceChartsRequireCompletePairSeparation(weight: Double) throws {
        func plane(offset: Double) -> BSplineSurface3D {
            BSplineSurface3D(uDegree: 1, vDegree: 1,
                uKnots: [0, 0, 1, 1], vKnots: [0, 0, 1, 1],
                controlPoints: [0.0, 1.0].map { y in
                    [0.0, 1.0].map { x in Point3D(x: x, y: y, z: x + offset) }
                }, weights: [[1, weight], [weight, 1]])
        }
        let first = plane(offset: 0)
        // Overlapping Cartesian hulls require subdivision, not chart adjacency.
        try BSplineSurfaceEmbeddingValidator().validateSeparation(
            first: first, second: plane(offset: 0.5), tolerance: .standard)
        try BSplineSurfaceEmbeddingValidator(maximumPairSubdivisionDepth: 0, maximumPairCellCount: 1)
            .validateSeparation(first: first, second: plane(offset: 2), tolerance: .standard)
        try BSplineSurfaceEmbeddingValidator(maximumPairSubdivisionDepth: 0)
            .validateSeparation(first: first, second: plane(offset: 0.5), tolerance: .standard)
        for second in [first] {
            do {
                try BSplineSurfaceEmbeddingValidator(maximumPairSubdivisionDepth: 0)
                    .validateSeparation(first: first, second: second, tolerance: .standard)
                Issue.record("Unresolved chart pairs must not pass separation.")
            } catch let error as KernelError {
                #expect(error.code == .resourceLimitExceeded)
            }
        }
    }

    @Test func separateSurfacePairsShareOneRequestBudget() throws {
        func strip(z: Double) -> BSplineSurface3D {
            BSplineSurface3D(uDegree: 1, vDegree: 1,
                uKnots: [0, 0, 1, 2, 2], vKnots: [0, 0, 1, 1],
                controlPoints: [0.0, 1.0].map { y in
                    [0.0, 1.0, 2.0].map { x in Point3D(x: x, y: y, z: z) }
                })
        }
        let first = strip(z: 0), second = strip(z: 1)
        try BSplineSurfaceEmbeddingValidator(maximumPairCellCount: 4)
            .validateSeparation(first: first, second: second, tolerance: .standard)
        do {
            try BSplineSurfaceEmbeddingValidator(maximumPairCellCount: 3)
                .validateSeparation(first: first, second: second, tolerance: .standard)
            Issue.record("Every root pair must consume the common budget, including hull exclusions.")
        } catch let error as KernelError {
            #expect(error.code == .resourceLimitExceeded)
        }
    }

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

    @Test func globalProjectionAvoidsRedundantPairEnumeration() throws {
        let surface = BSplineSurface3D(uDegree: 1, vDegree: 1,
            uKnots: [0, 0, 1, 2, 3, 4, 4], vKnots: [0, 0, 1, 1],
            controlPoints: [0.0, 1.0].map { y in
                (0...4).map { Point3D(x: Double($0), y: y, z: 0) }
            })
        try BSplineSurfaceEmbeddingValidator(maximumLocalSubdivisionDepth: 0,
            maximumCellCount: 4, maximumPairSubdivisionDepth: 0, maximumPairCellCount: 1)
            .validate(surface, uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: .standard)
        do {
            try BSplineSurfaceEmbeddingValidator(maximumLocalSubdivisionDepth: 0,
                maximumCellCount: 4, maximumPairSubdivisionDepth: 0, maximumPairCellCount: 0)
                .validate(surface, uDomain: surface.uDomain, vDomain: surface.vDomain, tolerance: .standard)
            Issue.record("A global certificate must not bypass invalid budget validation.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
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

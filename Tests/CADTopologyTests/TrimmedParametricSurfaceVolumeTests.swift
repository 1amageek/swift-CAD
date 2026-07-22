import CADCore
import CADGeometry
import Foundation
@testable import CADTopology
import Testing

@Suite("Trimmed parametric surface volume")
struct TrimmedParametricSurfaceVolumeTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func closedCurvedBSplineSolidUsesBoundaryIntegralWithoutMeshFallback() throws {
        let width = 2.0
        let depth = 3.0
        let height = 4.0
        let topInteriorRise = 2.0
        let expectedVolume = width * depth
            * (height + topInteriorRise * 0.25)
        let fixture = try makeBSplineBox(
            width: width,
            depth: depth,
            height: height,
            topInteriorRise: topInteriorRise
        )
        let shell = try #require(fixture.model.shells[fixture.shellID])

        try fixture.model.validate(level: .exact, tolerance: tolerance)
        #expect(try AnalyticPrismaticVolumeEvaluator().volume(
            of: shell,
            in: fixture.model,
            tolerance: tolerance
        ) == nil)
        #expect(try TrimmedAnalyticSurfaceVolumeEvaluator().volume(
            of: shell,
            in: fixture.model,
            tolerance: tolerance
        ) == nil)
        let directResult = try TrimmedParametricSurfaceVolumeEvaluator().volume(
            of: shell,
            in: fixture.model,
            tolerance: tolerance
        )
        let direct = try #require(directResult)
        let certifiedBoundsResult = try TrimmedParametricSurfaceVolumeEvaluator().volumeBounds(
            of: shell,
            in: fixture.model,
            tolerance: tolerance
        )
        let certifiedBounds = try #require(certifiedBoundsResult)
        let publicVolume = try fixture.model.volume(tolerance: tolerance)

        #expect(certifiedBounds.lower <= expectedVolume)
        #expect(certifiedBounds.upper >= expectedVolume)
        #expect(certifiedBounds.errorRadius <= tolerance.distance)
        #expect(abs(direct - expectedVolume) <= tolerance.distance)
        #expect(abs(publicVolume - expectedVolume) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonuniformMultiSpanRationalPlanarFaceReturnsCertifiedBounds() throws {
        let fixture = try makeBSplineBox(
            width: 2.0,
            depth: 3.0,
            height: 4.0,
            topInteriorRise: 0.0,
            topInteriorWeight: 2.0,
            topHasInteriorKnots: true
        )
        let shell = try #require(fixture.model.shells[fixture.shellID])

        try fixture.model.validate(level: .exact, tolerance: tolerance)
        let boundsResult = try TrimmedParametricSurfaceVolumeEvaluator().volumeBounds(
            of: shell,
            in: fixture.model,
            tolerance: tolerance
        )
        let bounds = try #require(boundsResult)
        let expectedVolume = 24.0
        let publicVolume = try fixture.model.volume(tolerance: tolerance)

        #expect(bounds.lower <= expectedVolume)
        #expect(bounds.upper >= expectedVolume)
        #expect(bounds.errorRadius <= tolerance.distance)
        #expect(abs(publicVolume - expectedVolume) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func exhaustedCoefficientBudgetReturnsTypedResourceDiagnostic() throws {
        let fixture = try makeBSplineBox(
            width: 2.0,
            depth: 3.0,
            height: 4.0,
            topInteriorRise: 2.0
        )
        let shell = try #require(fixture.model.shells[fixture.shellID])

        do {
            _ = try TrimmedParametricSurfaceVolumeEvaluator(
                maximumCoefficientOperations: 1
            ).volumeBounds(
                of: shell,
                in: fixture.model,
                tolerance: tolerance
            )
            Issue.record("The certified volume proof budget must be enforced.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func exhaustedRationalCellBudgetReturnsTypedResourceDiagnostic() throws {
        let fixture = try makeBSplineBox(
            width: 2.0,
            depth: 3.0,
            height: 4.0,
            topInteriorRise: 1.0,
            topInteriorWeight: 2.0
        )
        let shell = try #require(fixture.model.shells[fixture.shellID])

        do {
            _ = try TrimmedParametricSurfaceVolumeEvaluator(
                maximumRationalCellCount: 0
            ).volumeBounds(
                of: shell,
                in: fixture.model,
                tolerance: tolerance
            )
            Issue.record("The certified rational volume cell budget must be enforced.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func multiSpanSaddleFluxUsesCertifiedKnotExtraction() throws {
        let result = try CertifiedRationalBezierSurfaceFluxIntegrator().integrate(
            surface: multiSpanSaddleSurface(),
            uLower: 0.0,
            uUpper: 1.0,
            vLower: 0.0,
            vUpper: 1.0,
            reference: .origin,
            requestedError: 1.0e-8,
            tolerance: tolerance
        )
        let bounds = try #require(result)
        let expected = -1.0 / 12.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= 1.0e-8)
    }

    @Test(.timeLimit(.minutes(1)))
    func doublyNonClampedSurfaceFluxUsesEveryActiveSpan() throws {
        let surface = doublyNonClampedSaddleSurface()
        let result = try CertifiedRationalBezierSurfaceFluxIntegrator().integrate(
            surface: surface,
            uLower: 0.5,
            uUpper: 1.5,
            vLower: 0.5,
            vUpper: 1.5,
            reference: .origin,
            requestedError: 1.0e-9,
            tolerance: tolerance
        )
        let bounds = try #require(result)
        let expected = -1.0 / 3.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= 1.0e-9)
    }

    @Test(.timeLimit(.minutes(1)))
    func triangularTrimOnDoublyNonClampedSurfaceIsCertified() throws {
        let result = try TrimmedParametricSurfaceVolumeEvaluator()
            .rationalLoopVolumeBounds(
                surface: doublyNonClampedSaddleSurface(),
                parameterCurves: [
                    .constantV(v: 0.5, uStart: 0.5, uEnd: 1.5),
                    .affine(
                        origin: Point2D(x: 1.5, y: 0.5),
                        direction: Point2D(x: -1.0, y: 1.0),
                        startParameter: 0.0,
                        endParameter: 1.0
                    ),
                    .constantU(u: 0.5, vStart: 1.5, vEnd: 0.5),
                ],
                role: .outer,
                reference: .origin,
                requestedWidth: 1.0e-8,
                tolerance: tolerance
            )
        let bounds = try #require(result)
        let expected = -1.0 / 9.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= 1.0e-8)
    }

    @Test(.timeLimit(.minutes(1)))
    func triangularTrimOnNonClampedRationalSurfaceIsCertified() throws {
        let result = try TrimmedParametricSurfaceVolumeEvaluator()
            .rationalLoopVolumeBounds(
                surface: doublyNonClampedProjectivePlaneSurface(),
                parameterCurves: [
                    .constantV(v: 0.5, uStart: 0.5, uEnd: 1.5),
                    .affine(
                        origin: Point2D(x: 1.5, y: 0.5),
                        direction: Point2D(x: -1.0, y: 1.0),
                        startParameter: 0.0,
                        endParameter: 1.0
                    ),
                    .constantU(u: 0.5, vStart: 1.5, vEnd: 0.5),
                ],
                role: .outer,
                reference: .origin,
                requestedWidth: tolerance.distance,
                tolerance: tolerance
            )
        let bounds = try #require(result)
        let expected = 2.0 / 9.0 + log(3.0 / 5.0) / 3.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonDyadicKnotCrossingCurveUsesCertifiedSeamEnclosure() throws {
        let surface = doublyNonClampedProjectivePlaneSurface()
        let preparedField = try CertifiedRationalBezierSurfaceFluxIntegrator()
            .preparedField(
                surface: surface,
                reference: .origin,
                includeFluxNumerator: false,
                tolerance: tolerance
            )
        let field = try #require(
            preparedField
        )
        let result = try CertifiedAnalyticPcurveFluxIntegrator()
            .rationalPlanarAreaBounds(
                for: .affine(
                    origin: Point2D(x: 1.5, y: 0.5),
                    direction: Point2D(x: -0.75, y: 1.0),
                    startParameter: 0.0,
                    endParameter: 1.0
                ),
                field: field,
                projection: .normalZ,
                requestedWidth: tolerance.distance,
                tolerance: tolerance
            )
        let bounds = try #require(result)
        let expected = 29.0 / 35.0 + 4.0 * log(7.0 / 10.0) / 3.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect((bounds.upper - bounds.lower) * 0.5 <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonplanarNonDyadicKnotCrossingCurveIsCertified() throws {
        let surface = doublyNonClampedSaddleSurface()
        let preparedField = try CertifiedRationalBezierSurfaceFluxIntegrator()
            .preparedField(
                surface: surface,
                reference: .origin,
                tolerance: tolerance
            )
        let field = try #require(preparedField)
        let result = try CertifiedAnalyticPcurveFluxIntegrator()
            .rationalSurfaceBounds(
                for: .affine(
                    origin: Point2D(x: 1.5, y: 0.5),
                    direction: Point2D(x: -0.75, y: 1.0),
                    startParameter: 0.0,
                    endParameter: 1.0
                ),
                field: field,
                uBase: 0.5,
                requestedWidth: tolerance.distance,
                tolerance: tolerance
            )
        let bounds = try #require(result)
        let expected = -59.0 / 384.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect((bounds.upper - bounds.lower) * 0.5 <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonplanarHarmonicKnotCrossingCurveIsCertified() throws {
        let surface = doublyNonClampedSaddleSurface()
        let preparedField = try CertifiedRationalBezierSurfaceFluxIntegrator()
            .preparedField(
                surface: surface,
                reference: .origin,
                tolerance: tolerance
            )
        let field = try #require(preparedField)
        let result = try CertifiedAnalyticPcurveFluxIntegrator()
            .rationalSurfaceBounds(
                for: .harmonic(
                    center: Point2D(x: 1.0, y: 1.0),
                    cosine: Point2D(x: 0.4, y: 0.0),
                    sine: Point2D(x: 0.0, y: 0.4),
                    startParameter: 0.0,
                    endParameter: 2.0
                ),
                field: field,
                uBase: 0.5,
                requestedWidth: tolerance.distance,
                tolerance: tolerance
            )
        let bounds = try #require(result)
        let expected = -119.0 / 1_800.0
            - 29.0 * sin(2.0) / 500.0
            + 83.0 * cos(4.0) / 15_000.0
            + 2.0 * cos(2.0) / 375.0
            + cos(8.0) / 7_500.0
            - sin(6.0) / 1_125.0
            + 2.0 * cos(6.0) / 1_125.0
            - sin(4.0) / 75.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect((bounds.upper - bounds.lower) * 0.5 <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func nonplanarRationalBSplineKnotCrossingCurveIsCertified() throws {
        let surface = doublyNonClampedSaddleSurface()
        let preparedField = try CertifiedRationalBezierSurfaceFluxIntegrator()
            .preparedField(
                surface: surface,
                reference: .origin,
                tolerance: tolerance
            )
        let field = try #require(preparedField)
        let curve = BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 1.5, y: 0.5),
                Point2D(x: 0.5, y: 1.5),
            ],
            weights: [1.0, 2.0]
        )
        let result = try CertifiedAnalyticPcurveFluxIntegrator()
            .rationalSurfaceBounds(
                for: .bSpline(curve),
                field: field,
                uBase: 0.5,
                requestedWidth: tolerance.distance,
                tolerance: tolerance
            )
        let bounds = try #require(result)
        let expected = -1.0 / 9.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect((bounds.upper - bounds.lower) * 0.5 <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func exhaustedKnotExtractionBudgetReturnsTypedResourceDiagnostic() throws {
        do {
            _ = try CertifiedRationalBezierSurfaceFluxIntegrator(
                maximumExtractionControlOperations: 0
            ).integrate(
                surface: multiSpanSaddleSurface(),
                uLower: 0.0,
                uUpper: 1.0,
                vLower: 0.0,
                vUpper: 1.0,
                reference: .origin,
                requestedError: 1.0e-8,
                tolerance: tolerance
            )
            Issue.record("The certified knot-extraction budget must be enforced.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .resourceLimitExceeded)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func triangularPolynomialTrimReturnsCertifiedSaddleContribution() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 1.0),
                ],
            ]
        )
        let result = try TrimmedParametricSurfaceVolumeEvaluator()
            .polynomialLoopVolumeBounds(
                surface: surface,
                parameterCurves: [
                    .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
                    .affine(
                        origin: Point2D(x: 1.0, y: 0.0),
                        direction: Point2D(x: -1.0, y: 1.0),
                        startParameter: 0.0,
                        endParameter: 1.0
                    ),
                    .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0),
                ],
                role: .outer,
                reference: .origin,
                requestedWidth: 1.0e-10,
                tolerance: tolerance
            )
        let bounds = try #require(result)
        let expected = -1.0 / 72.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= 1.0e-10)
    }

    @Test(.timeLimit(.minutes(1)))
    func triangularRationalTrimReturnsCertifiedPlanarContribution() throws {
        let surface = BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 3.0),
                    Point3D(x: 1.0, y: 0.0, z: 3.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 3.0),
                    Point3D(x: 1.0, y: 1.0, z: 3.0),
                ],
            ],
            weights: [
                [1.0, 2.0],
                [3.0, 6.0],
            ]
        )
        let result = try TrimmedParametricSurfaceVolumeEvaluator()
            .rationalLoopVolumeBounds(
                surface: surface,
                parameterCurves: [
                    .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
                    .affine(
                        origin: Point2D(x: 1.0, y: 0.0),
                        direction: Point2D(x: -1.0, y: 1.0),
                        startParameter: 0.0,
                        endParameter: 1.0
                    ),
                    .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0),
                ],
                role: .outer,
                reference: .origin,
                requestedWidth: 1.0e-7,
                tolerance: tolerance
            )
        let bounds = try #require(result)
        let expected = 6.0 / 5.0
            - 12.0 * log(2.0) / 25.0
            - 6.0 * log(3.0 / 2.0) / 25.0

        #expect(bounds.lower <= expected)
        #expect(bounds.upper >= expected)
        #expect(bounds.errorRadius <= 1.0e-7)
    }

    private func makeBSplineBox(
        width: Double,
        depth: Double,
        height: Double,
        topInteriorRise: Double,
        topInteriorWeight: Double? = nil,
        topHasInteriorKnots: Bool = false
    ) throws -> Fixture {
        let points = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: width, y: 0.0, z: 0.0),
            Point3D(x: width, y: depth, z: 0.0),
            Point3D(x: 0.0, y: depth, z: 0.0),
            Point3D(x: 0.0, y: 0.0, z: height),
            Point3D(x: width, y: 0.0, z: height),
            Point3D(x: width, y: depth, z: height),
            Point3D(x: 0.0, y: depth, z: height),
        ]
        let faceCorners = [
            [0, 3, 2, 1],
            [4, 5, 6, 7],
            [0, 1, 5, 4],
            [3, 7, 6, 2],
            [0, 4, 7, 3],
            [1, 2, 6, 5],
        ]
        let vertexIDs = points.map { _ in VertexID() }
        var curves: [CurveID: Curve3D] = [:]
        var surfaces: [SurfaceID: Surface3D] = [:]
        var edges: [EdgeID: Edge] = [:]
        var edgeRecords: [UndirectedEdgeKey: EdgeRecord] = [:]
        var loops: [LoopID: Loop] = [:]
        var faces: [FaceID: Face] = [:]
        var faceIDs: [FaceID] = []
        let pcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
            .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0),
            .constantV(v: 1.0, uStart: 1.0, uEnd: 0.0),
            .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0),
        ]

        for (faceIndex, corners) in faceCorners.enumerated() {
            let surfaceID = SurfaceID()
            let loopID = LoopID()
            let faceID = FaceID()
            if faceIndex == 1 {
                let topSurface = curvedTopSurface(
                    width: width,
                    depth: depth,
                    height: height,
                    interiorRise: topInteriorRise,
                    interiorWeight: topInteriorWeight,
                    hasInteriorKnots: topHasInteriorKnots
                )
                surfaces[surfaceID] = .bSpline(topSurface)
            } else {
                surfaces[surfaceID] = .bSpline(cubicPlanarPatch(
                    bottomLeft: points[corners[0]],
                    bottomRight: points[corners[1]],
                    topRight: points[corners[2]],
                    topLeft: points[corners[3]]
                ))
            }
            var coedges: [Coedge] = []
            for localIndex in corners.indices {
                let startIndex = corners[localIndex]
                let endIndex = corners[(localIndex + 1) % corners.count]
                let key = UndirectedEdgeKey(startIndex, endIndex)
                let record: EdgeRecord
                if let existing = edgeRecords[key] {
                    record = existing
                } else {
                    let edgeID = EdgeID()
                    let curveID = CurveID()
                    let displacement = points[endIndex] - points[startIndex]
                    curves[curveID] = .bSpline(BSplineCurve3D(
                        degree: 3,
                        knots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
                        controlPoints: (0..<4).map { controlIndex in
                            points[startIndex]
                                + displacement * (Double(controlIndex) / 3.0)
                        }
                    ))
                    edges[edgeID] = Edge(
                        id: edgeID,
                        curveID: curveID,
                        startVertexID: vertexIDs[startIndex],
                        endVertexID: vertexIDs[endIndex],
                        trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
                    )
                    record = EdgeRecord(
                        id: edgeID,
                        startVertexIndex: startIndex,
                        endVertexIndex: endIndex
                    )
                    edgeRecords[key] = record
                }
                let orientation: Orientation = record.startVertexIndex == startIndex
                    && record.endVertexIndex == endIndex
                    ? .forward
                    : .reversed
                coedges.append(Coedge(
                    edgeID: record.id,
                    orientation: orientation,
                    surfaceParameterCurve: pcurves[localIndex]
                ))
            }
            loops[loopID] = Loop(id: loopID, role: .outer, coedges: coedges)
            faces[faceID] = Face(
                id: faceID,
                surfaceID: surfaceID,
                loops: [loopID]
            )
            faceIDs.append(faceID)
        }

        let shellID = ShellID()
        let bodyID = BodyID()
        let vertices = Dictionary(uniqueKeysWithValues: vertexIDs.indices.map {
            (vertexIDs[$0], Vertex(id: vertexIDs[$0], point: points[$0]))
        })
        return Fixture(
            model: BRepModel(
                geometry: GeometryStore(curves: curves, surfaces: surfaces),
                bodies: [
                    bodyID: Body(id: bodyID, shellIDs: [shellID], kind: .solid),
                ],
                shells: [
                    shellID: Shell(id: shellID, faceIDs: faceIDs),
                ],
                faces: faces,
                loops: loops,
                edges: edges,
                vertices: vertices
            ),
            shellID: shellID
        )
    }

    private func curvedTopSurface(
        width: Double,
        depth: Double,
        height: Double,
        interiorRise: Double,
        interiorWeight: Double?,
        hasInteriorKnots: Bool
    ) -> BSplineSurface3D {
        let parameters = hasInteriorKnots
            ? [0.0, 1.0 / 6.0, 1.0 / 3.0, 0.5, 2.0 / 3.0, 5.0 / 6.0, 1.0]
            : [0.0, 1.0 / 3.0, 2.0 / 3.0, 1.0]
        let lastIndex = parameters.count - 1
        let controls = parameters.indices.map { vIndex in
            parameters.indices.map { uIndex in
                Point3D(
                    x: width * parameters[uIndex],
                    y: depth * parameters[vIndex],
                    z: height + (
                        uIndex > 0 && uIndex < lastIndex
                            && vIndex > 0 && vIndex < lastIndex
                            ? interiorRise
                            : 0.0
                    )
                )
            }
        }
        let weights = interiorWeight.map { value in
            parameters.indices.map { vIndex in
                parameters.indices.map { uIndex in
                    uIndex > 0 && uIndex < lastIndex
                        && vIndex > 0 && vIndex < lastIndex
                        ? value
                        : 1.0
                }
            }
        }
        let knots = hasInteriorKnots
            ? [0.0, 0.0, 0.0, 0.0, 0.5, 0.5, 0.5, 1.0, 1.0, 1.0, 1.0]
            : [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0]
        return BSplineSurface3D(
            uDegree: 3,
            vDegree: 3,
            uKnots: knots,
            vKnots: knots,
            controlPoints: controls,
            weights: weights
        )
    }

    private func multiSpanSaddleSurface() -> BSplineSurface3D {
        let parameters = [0.0, 0.25, 0.75, 1.0]
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 0.5, 1.0, 1.0, 1.0],
            controlPoints: parameters.map { v in
                parameters.map { u in
                    Point3D(x: u, y: v, z: u * v)
                }
            }
        )
    }

    private func doublyNonClampedSaddleSurface() -> BSplineSurface3D {
        let grevilleParameters = [0.25, 0.75, 1.25, 1.75]
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.5, 1.0, 1.5, 2.0, 2.0],
            vKnots: [0.0, 0.0, 0.5, 1.0, 1.5, 2.0, 2.0],
            controlPoints: grevilleParameters.map { v in
                grevilleParameters.map { u in
                    Point3D(x: u, y: v, z: u * v)
                }
            }
        )
    }

    private func doublyNonClampedProjectivePlaneSurface() -> BSplineSurface3D {
        let grevilleParameters = [0.25, 0.75, 1.25, 1.75]
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.5, 1.0, 1.5, 2.0, 2.0],
            vKnots: [0.0, 0.0, 0.5, 1.0, 1.5, 2.0, 2.0],
            controlPoints: grevilleParameters.map { v in
                grevilleParameters.map { u in
                    Point3D(x: u / (u + 1.0), y: v, z: 1.0)
                }
            },
            weights: grevilleParameters.map { _ in
                grevilleParameters.map { $0 + 1.0 }
            }
        )
    }

    private func cubicPlanarPatch(
        bottomLeft: Point3D,
        bottomRight: Point3D,
        topRight: Point3D,
        topLeft: Point3D
    ) -> BSplineSurface3D {
        let controls = (0..<4).map { vIndex in
            let v = Double(vIndex) / 3.0
            let left = bottomLeft + (topLeft - bottomLeft) * v
            let right = bottomRight + (topRight - bottomRight) * v
            return (0..<4).map { uIndex in
                left + (right - left) * (Double(uIndex) / 3.0)
            }
        }
        return BSplineSurface3D(
            uDegree: 3,
            vDegree: 3,
            uKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0],
            controlPoints: controls
        )
    }

    private struct Fixture {
        let model: BRepModel
        let shellID: ShellID
    }

    private struct EdgeRecord {
        let id: EdgeID
        let startVertexIndex: Int
        let endVertexIndex: Int
    }

    private struct UndirectedEdgeKey: Hashable {
        let lower: Int
        let upper: Int

        init(_ first: Int, _ second: Int) {
            lower = min(first, second)
            upper = max(first, second)
        }
    }
}

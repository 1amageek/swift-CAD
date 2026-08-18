import CADCore
import CADGeometry
import Foundation
@testable import CADTopology
import Testing

@Suite("Trimmed rational B-rep volume")
struct TrimmedRationalBRepVolumeTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func triangularRationalPrismUsesValidatedBRepEvaluationPath() throws {
        let height = 3.0
        let fixture = makeTriangularRationalPrism(height: height)

        let mappedTriangleArea = 6.0 / 5.0
            - 12.0 * log(2.0) / 25.0
            - 6.0 * log(3.0 / 2.0) / 25.0
        let expectedVolume = height * mappedTriangleArea
        let publicVolume = try fixture.model.volume(tolerance: tolerance)

        #expect(abs(publicVolume - expectedVolume) <= tolerance.distance)
        #expect(abs(try fixture.model.volume(of: fixture.bodyID, tolerance: tolerance) - expectedVolume) <= tolerance.distance)
    }

    @Test(.timeLimit(.minutes(1)))
    func reversedOnlySolidShellIsNotAcceptedAsPositiveMaterial() throws {
        let fixture = makeTriangularRationalPrism(height: 3.0)
        var model = fixture.model
        guard var shell = model.shells[fixture.shellID] else {
            Issue.record("Fixture shell is missing.")
            return
        }
        shell.orientation = .reversed
        model.shells[fixture.shellID] = shell

        #expect(throws: KernelError.self) {
            try model.validate(tolerance: tolerance)
        }
        #expect(throws: KernelError.self) {
            _ = try model.volume(of: fixture.bodyID, tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func triangularRationalPrismPassesExactPcurveValidation() throws {
        let fixture = makeTriangularRationalPrism(height: 3.0)

        try fixture.model.validate(level: .exact, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func multiSpanSaddlePrismCertifiesRationalKnotCrossingThroughPublicVolume() throws {
        let height = 2.5
        let fixture = try makeMultiSpanSaddlePrism(height: height)
        let validated = try ValidatedBRepModel(
            fixture.model,
            tolerance: tolerance,
            validationLevel: .volumetric
        )

        let volume = try #require(validated.volume)

        #expect(abs(volume - height * 0.5) <= tolerance.distance)
    }

    private func makeTriangularRationalPrism(height: Double) -> Fixture {
        let bottomPoints = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ]
        let topPoints = bottomPoints.map {
            Point3D(x: $0.x, y: $0.y, z: height)
        }
        let points = bottomPoints + topPoints
        let vertexIDs = points.map { _ in VertexID() }
        let vertices = Dictionary(uniqueKeysWithValues: points.indices.map {
            (vertexIDs[$0], Vertex(id: vertexIDs[$0], point: points[$0]))
        })

        var curves: [CurveID: Curve3D] = [:]
        var surfaces: [SurfaceID: Surface3D] = [:]
        var edges: [EdgeID: Edge] = [:]
        var loops: [LoopID: Loop] = [:]
        var faces: [FaceID: Face] = [:]

        var bottomEdgeIDs: [EdgeID] = []
        var topEdgeIDs: [EdgeID] = []
        var boundaryCurves: [BoundaryCurve] = []
        for boundaryIndex in 0..<3 {
            let bottomCurve = boundaryCurve(
                boundaryIndex: boundaryIndex,
                z: 0.0
            )
            let topCurve = boundaryCurve(
                boundaryIndex: boundaryIndex,
                z: height
            )
            boundaryCurves.append(topCurve)
            let startIndex = boundaryIndex
            let endIndex = (boundaryIndex + 1) % 3
            bottomEdgeIDs.append(addEdge(
                curve: bottomCurve,
                startVertexID: vertexIDs[startIndex],
                endVertexID: vertexIDs[endIndex],
                curves: &curves,
                edges: &edges
            ))
            topEdgeIDs.append(addEdge(
                curve: topCurve,
                startVertexID: vertexIDs[startIndex + 3],
                endVertexID: vertexIDs[endIndex + 3],
                curves: &curves,
                edges: &edges
            ))
        }

        var verticalEdgeIDs: [EdgeID] = []
        for vertexIndex in 0..<3 {
            verticalEdgeIDs.append(addEdge(
                curve: BoundaryCurve(
                    degree: 1,
                    knots: [0.0, 0.0, 1.0, 1.0],
                    controlPoints: [bottomPoints[vertexIndex], topPoints[vertexIndex]],
                    weights: [1.0, 1.0]
                ),
                startVertexID: vertexIDs[vertexIndex],
                endVertexID: vertexIDs[vertexIndex + 3],
                curves: &curves,
                edges: &edges
            ))
        }

        let trianglePcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
            .affine(
                origin: Point2D(x: 1.0, y: 0.0),
                direction: Point2D(x: -1.0, y: 1.0),
                startParameter: 0.0,
                endParameter: 1.0
            ),
            .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0),
        ]

        let bottomSurfaceID = SurfaceID()
        surfaces[bottomSurfaceID] = .bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [bottomPoints[0], bottomPoints[2]],
                [bottomPoints[1], Point3D(x: 1.0, y: 1.0, z: 0.0)],
            ],
            weights: [
                [1.0, 3.0],
                [2.0, 6.0],
            ]
        ))
        let bottomLoopID = LoopID()
        loops[bottomLoopID] = Loop(
            id: bottomLoopID,
            role: .outer,
            coedges: zip(
                [bottomEdgeIDs[2], bottomEdgeIDs[1], bottomEdgeIDs[0]],
                trianglePcurves
            ).map {
                Coedge(
                    edgeID: $0.0,
                    orientation: .reversed,
                    surfaceParameterCurve: $0.1
                )
            }
        )
        let bottomFaceID = FaceID()
        faces[bottomFaceID] = Face(
            id: bottomFaceID,
            surfaceID: bottomSurfaceID,
            loops: [bottomLoopID]
        )

        let topSurfaceID = SurfaceID()
        surfaces[topSurfaceID] = .bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [0.0, 0.0, 1.0, 1.0],
            vKnots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                [topPoints[0], topPoints[1]],
                [topPoints[2], Point3D(x: 1.0, y: 1.0, z: height)],
            ],
            weights: [
                [1.0, 2.0],
                [3.0, 6.0],
            ]
        ))
        let topLoopID = LoopID()
        loops[topLoopID] = Loop(
            id: topLoopID,
            role: .outer,
            coedges: zip(topEdgeIDs, trianglePcurves).map {
                Coedge(
                    edgeID: $0.0,
                    orientation: .forward,
                    surfaceParameterCurve: $0.1
                )
            }
        )
        let topFaceID = FaceID()
        faces[topFaceID] = Face(
            id: topFaceID,
            surfaceID: topSurfaceID,
            loops: [topLoopID]
        )

        var faceIDs = [bottomFaceID, topFaceID]
        let rectanglePcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
            .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0),
            .constantV(v: 1.0, uStart: 1.0, uEnd: 0.0),
            .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0),
        ]
        for boundaryIndex in 0..<3 {
            let boundary = boundaryCurves[boundaryIndex]
            let surfaceID = SurfaceID()
            surfaces[surfaceID] = .bSpline(BSplineSurface3D(
                uDegree: boundary.degree,
                vDegree: 1,
                uKnots: boundary.knots,
                vKnots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    boundary.controlPoints.map {
                        Point3D(x: $0.x, y: $0.y, z: 0.0)
                    },
                    boundary.controlPoints,
                ],
                weights: [boundary.weights, boundary.weights]
            ))
            let loopID = LoopID()
            let endIndex = (boundaryIndex + 1) % 3
            let sideEdgeIDs = [
                bottomEdgeIDs[boundaryIndex],
                verticalEdgeIDs[endIndex],
                topEdgeIDs[boundaryIndex],
                verticalEdgeIDs[boundaryIndex],
            ]
            let orientations: [Orientation] = [
                .forward,
                .forward,
                .reversed,
                .reversed,
            ]
            loops[loopID] = Loop(
                id: loopID,
                role: .outer,
                coedges: sideEdgeIDs.indices.map {
                    Coedge(
                        edgeID: sideEdgeIDs[$0],
                        orientation: orientations[$0],
                        surfaceParameterCurve: rectanglePcurves[$0]
                    )
                }
            )
            let faceID = FaceID()
            faces[faceID] = Face(
                id: faceID,
                surfaceID: surfaceID,
                loops: [loopID]
            )
            faceIDs.append(faceID)
        }

        let shellID = ShellID()
        let bodyID = BodyID()
        return Fixture(
            model: BRepModel(
                geometry: GeometryStore(curves: curves, surfaces: surfaces),
                bodies: [
                    bodyID: Body(
                        id: bodyID,
                        solidComponents: [SolidShellComponent(outerShellID: shellID)]
                    ),
                ],
                shells: [
                    shellID: Shell(id: shellID, faceIDs: faceIDs),
                ],
                faces: faces,
                loops: loops,
                edges: edges,
                vertices: vertices
            ),
            shellID: shellID,
            bodyID: bodyID
        )
    }

    private func makeMultiSpanSaddlePrism(height: Double) throws -> Fixture {
        let parameterVertices = [
            SurfaceParameter(u: 0.5, v: 0.5),
            SurfaceParameter(u: 1.5, v: 0.5),
            SurfaceParameter(u: 0.5, v: 1.5),
        ]
        let bottomPoints = parameterVertices.map {
            Point3D(x: $0.u, y: $0.v, z: $0.u * $0.v)
        }
        let topPoints = bottomPoints.map {
            Point3D(x: $0.x, y: $0.y, z: $0.z + height)
        }
        let points = bottomPoints + topPoints
        let vertexIDs = points.map { _ in VertexID() }
        let vertices = Dictionary(uniqueKeysWithValues: points.indices.map {
            (vertexIDs[$0], Vertex(id: vertexIDs[$0], point: points[$0]))
        })

        var curves: [CurveID: Curve3D] = [:]
        var surfaces: [SurfaceID: Surface3D] = [:]
        var edges: [EdgeID: Edge] = [:]
        var loops: [LoopID: Loop] = [:]
        var faces: [FaceID: Face] = [:]

        let bottomBoundaryCurves = (0..<3).map {
            saddleBoundaryCurve(boundaryIndex: $0, height: 0.0)
        }
        let topBoundaryCurves = (0..<3).map {
            saddleBoundaryCurve(boundaryIndex: $0, height: height)
        }
        var bottomEdgeIDs: [EdgeID] = []
        var topEdgeIDs: [EdgeID] = []
        for boundaryIndex in 0..<3 {
            let endIndex = (boundaryIndex + 1) % 3
            bottomEdgeIDs.append(addEdge(
                curve: bottomBoundaryCurves[boundaryIndex],
                startVertexID: vertexIDs[boundaryIndex],
                endVertexID: vertexIDs[endIndex],
                curves: &curves,
                edges: &edges
            ))
            topEdgeIDs.append(addEdge(
                curve: topBoundaryCurves[boundaryIndex],
                startVertexID: vertexIDs[boundaryIndex + 3],
                endVertexID: vertexIDs[endIndex + 3],
                curves: &curves,
                edges: &edges
            ))
        }

        var verticalEdgeIDs: [EdgeID] = []
        for vertexIndex in 0..<3 {
            verticalEdgeIDs.append(addEdge(
                curve: BoundaryCurve(
                    degree: 1,
                    knots: [0.0, 0.0, 1.0, 1.0],
                    controlPoints: [bottomPoints[vertexIndex], topPoints[vertexIndex]],
                    weights: [1.0, 1.0]
                ),
                startVertexID: vertexIDs[vertexIndex],
                endVertexID: vertexIDs[vertexIndex + 3],
                curves: &curves,
                edges: &edges
            ))
        }

        let rationalDiagonal = SurfaceParameterCurve.bSpline(BSplineCurve2D(
            degree: 1,
            knots: [0.0, 0.0, 1.0, 1.0],
            controlPoints: [
                Point2D(x: 1.5, y: 0.5),
                Point2D(x: 0.5, y: 1.5),
            ],
            weights: [1.0, 2.0]
        ))
        let topPcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0.5, uStart: 0.5, uEnd: 1.5),
            rationalDiagonal,
            .constantU(u: 0.5, vStart: 1.5, vEnd: 0.5),
        ]
        let bottomPcurves: [SurfaceParameterCurve] = [
            .constantU(u: 0.5, vStart: 0.5, vEnd: 1.5),
            try rationalDiagonal.reversed(tolerance: tolerance),
            .constantV(v: 0.5, uStart: 1.5, uEnd: 0.5),
        ]

        let bottomSurfaceID = SurfaceID()
        surfaces[bottomSurfaceID] = .bSpline(saddleSurface(height: 0.0))
        let bottomLoopID = LoopID()
        loops[bottomLoopID] = Loop(
            id: bottomLoopID,
            role: .outer,
            coedges: zip(
                [bottomEdgeIDs[2], bottomEdgeIDs[1], bottomEdgeIDs[0]],
                bottomPcurves
            ).map {
                Coedge(
                    edgeID: $0.0,
                    orientation: .reversed,
                    surfaceParameterCurve: $0.1
                )
            }
        )
        let bottomFaceID = FaceID()
        faces[bottomFaceID] = Face(
            id: bottomFaceID,
            surfaceID: bottomSurfaceID,
            loops: [bottomLoopID],
            orientation: .reversed
        )

        let topSurfaceID = SurfaceID()
        surfaces[topSurfaceID] = .bSpline(saddleSurface(height: height))
        let topLoopID = LoopID()
        loops[topLoopID] = Loop(
            id: topLoopID,
            role: .outer,
            coedges: zip(topEdgeIDs, topPcurves).map {
                Coedge(
                    edgeID: $0.0,
                    orientation: .forward,
                    surfaceParameterCurve: $0.1
                )
            }
        )
        let topFaceID = FaceID()
        faces[topFaceID] = Face(
            id: topFaceID,
            surfaceID: topSurfaceID,
            loops: [topLoopID]
        )

        var faceIDs = [bottomFaceID, topFaceID]
        let rectanglePcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
            .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0),
            .constantV(v: 1.0, uStart: 1.0, uEnd: 0.0),
            .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0),
        ]
        for boundaryIndex in 0..<3 {
            let bottomBoundary = bottomBoundaryCurves[boundaryIndex]
            let topBoundary = topBoundaryCurves[boundaryIndex]
            let surfaceID = SurfaceID()
            surfaces[surfaceID] = .bSpline(BSplineSurface3D(
                uDegree: bottomBoundary.degree,
                vDegree: 1,
                uKnots: bottomBoundary.knots,
                vKnots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    bottomBoundary.controlPoints,
                    topBoundary.controlPoints,
                ],
                weights: [bottomBoundary.weights, topBoundary.weights]
            ))
            let endIndex = (boundaryIndex + 1) % 3
            let sideEdgeIDs = [
                bottomEdgeIDs[boundaryIndex],
                verticalEdgeIDs[endIndex],
                topEdgeIDs[boundaryIndex],
                verticalEdgeIDs[boundaryIndex],
            ]
            let orientations: [Orientation] = [
                .forward,
                .forward,
                .reversed,
                .reversed,
            ]
            let loopID = LoopID()
            loops[loopID] = Loop(
                id: loopID,
                role: .outer,
                coedges: sideEdgeIDs.indices.map {
                    Coedge(
                        edgeID: sideEdgeIDs[$0],
                        orientation: orientations[$0],
                        surfaceParameterCurve: rectanglePcurves[$0]
                    )
                }
            )
            let faceID = FaceID()
            faces[faceID] = Face(
                id: faceID,
                surfaceID: surfaceID,
                loops: [loopID]
            )
            faceIDs.append(faceID)
        }

        let shellID = ShellID()
        let bodyID = BodyID()
        return Fixture(
            model: BRepModel(
                geometry: GeometryStore(curves: curves, surfaces: surfaces),
                bodies: [
                    bodyID: Body(
                        id: bodyID,
                        solidComponents: [SolidShellComponent(outerShellID: shellID)]
                    ),
                ],
                shells: [
                    shellID: Shell(id: shellID, faceIDs: faceIDs),
                ],
                faces: faces,
                loops: loops,
                edges: edges,
                vertices: vertices
            ),
            shellID: shellID,
            bodyID: bodyID
        )
    }

    private func saddleSurface(height: Double) -> BSplineSurface3D {
        let grevilleParameters = [0.25, 0.75, 1.25, 1.75]
        return BSplineSurface3D(
            uDegree: 2,
            vDegree: 2,
            uKnots: [0.0, 0.0, 0.5, 1.0, 1.5, 2.0, 2.0],
            vKnots: [0.0, 0.0, 0.5, 1.0, 1.5, 2.0, 2.0],
            controlPoints: grevilleParameters.map { v in
                grevilleParameters.map { u in
                    Point3D(x: u, y: v, z: u * v + height)
                }
            }
        )
    }

    private func saddleBoundaryCurve(
        boundaryIndex: Int,
        height: Double
    ) -> BoundaryCurve {
        switch boundaryIndex {
        case 0:
            return BoundaryCurve(
                degree: 1,
                knots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 0.5, y: 0.5, z: 0.25 + height),
                    Point3D(x: 1.5, y: 0.5, z: 0.75 + height),
                ],
                weights: [1.0, 1.0]
            )
        case 1:
            return BoundaryCurve(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 1.5, y: 0.5, z: 0.75 + height),
                    Point3D(x: 1.0, y: 1.0, z: 1.25 + height),
                    Point3D(x: 0.5, y: 1.5, z: 0.75 + height),
                ],
                weights: [1.0, 2.0, 4.0]
            )
        default:
            return BoundaryCurve(
                degree: 1,
                knots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 0.5, y: 1.5, z: 0.75 + height),
                    Point3D(x: 0.5, y: 0.5, z: 0.25 + height),
                ],
                weights: [1.0, 1.0]
            )
        }
    }

    private func boundaryCurve(boundaryIndex: Int, z: Double) -> BoundaryCurve {
        switch boundaryIndex {
        case 0:
            return BoundaryCurve(
                degree: 1,
                knots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 0.0, y: 0.0, z: z),
                    Point3D(x: 1.0, y: 0.0, z: z),
                ],
                weights: [1.0, 2.0]
            )
        case 1:
            return BoundaryCurve(
                degree: 2,
                knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 1.0, y: 0.0, z: z),
                    Point3D(x: 6.0 / 7.0, y: 6.0 / 7.0, z: z),
                    Point3D(x: 0.0, y: 1.0, z: z),
                ],
                weights: [2.0, 3.5, 3.0]
            )
        default:
            return BoundaryCurve(
                degree: 1,
                knots: [0.0, 0.0, 1.0, 1.0],
                controlPoints: [
                    Point3D(x: 0.0, y: 1.0, z: z),
                    Point3D(x: 0.0, y: 0.0, z: z),
                ],
                weights: [3.0, 1.0]
            )
        }
    }

    private func addEdge(
        curve: BoundaryCurve,
        startVertexID: VertexID,
        endVertexID: VertexID,
        curves: inout [CurveID: Curve3D],
        edges: inout [EdgeID: Edge]
    ) -> EdgeID {
        let curveID = CurveID()
        let edgeID = EdgeID()
        curves[curveID] = .bSpline(BSplineCurve3D(
            degree: curve.degree,
            knots: curve.knots,
            controlPoints: curve.controlPoints,
            weights: curve.weights
        ))
        edges[edgeID] = Edge(
            id: edgeID,
            curveID: curveID,
            startVertexID: startVertexID,
            endVertexID: endVertexID,
            trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
        )
        return edgeID
    }

    private struct BoundaryCurve {
        let degree: Int
        let knots: [Double]
        let controlPoints: [Point3D]
        let weights: [Double]
    }

    private struct Fixture {
        let model: BRepModel
        let shellID: ShellID
        let bodyID: BodyID
    }
}

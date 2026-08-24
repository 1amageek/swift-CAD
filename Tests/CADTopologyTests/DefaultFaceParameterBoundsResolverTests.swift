import CADCore
import CADGeometry
import Testing
@testable import CADTopology

@Suite("Default face parameter bounds resolver")
struct DefaultFaceParameterBoundsResolverTests {
    @Test(.timeLimit(.minutes(1)))
    func exactRectanglePreservesItsParameterBounds() throws {
        let fixture = makeTrimmedModel(
            surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            pcurves: [
                .constantV(v: 0.2, uStart: -0.4, uEnd: 0.6),
                .constantU(u: 0.6, vStart: 0.2, vEnd: 0.9),
                .constantV(v: 0.9, uStart: 0.6, uEnd: -0.4),
                .constantU(u: -0.4, vStart: 0.9, vEnd: 0.2),
            ]
        )

        let bounds = try DefaultFaceParameterBoundsResolver().bounds(
            for: fixture.faceID,
            in: fixture.model,
            tolerance: .standard
        )

        #expect(bounds.u == (try ScalarInterval(lower: -0.4, upper: 0.6)))
        #expect(bounds.v == (try ScalarInterval(lower: 0.2, upper: 0.9)))
    }

    @Test(.timeLimit(.minutes(1)))
    func generalPcurvesProduceCertifiedEnclosingBounds() throws {
        let fixture = makeTrimmedModel(
            surface: .plane(Plane3D(origin: .origin, normal: .unitZ)),
            pcurves: [
                .affine(
                    origin: Point2D(x: -0.3, y: 0.1),
                    direction: Point2D(x: 1.1, y: 0.2),
                    startParameter: 0.0,
                    endParameter: 1.0
                ),
                .constantU(u: 0.8, vStart: 0.3, vEnd: 1.2),
                .affine(
                    origin: Point2D(x: 0.8, y: 1.2),
                    direction: Point2D(x: -1.1, y: -1.1),
                    startParameter: 0.0,
                    endParameter: 1.0
                ),
            ]
        )

        let bounds = try DefaultFaceParameterBoundsResolver().bounds(
            for: fixture.faceID,
            in: fixture.model,
            tolerance: .standard
        )

        #expect(bounds.u.lower <= -0.3)
        #expect(bounds.u.upper >= 0.8)
        #expect(bounds.v.lower <= 0.1)
        #expect(bounds.v.upper >= 1.2)
        #expect(bounds.u.lower >= -0.300_001)
        #expect(bounds.u.upper <= 0.800_001)
        #expect(bounds.v.lower >= 0.099_999)
        #expect(bounds.v.upper <= 1.200_001)
    }

    @Test(.timeLimit(.minutes(1)))
    func untrimmedBoundedSurfaceUsesItsSupportDomain() throws {
        let surface = Surface3D.bSpline(BSplineSurface3D(
            uDegree: 1,
            vDegree: 1,
            uKnots: [2.0, 2.0, 4.0, 4.0],
            vKnots: [3.0, 3.0, 7.0, 7.0],
            controlPoints: [
                [
                    Point3D(x: 0.0, y: 0.0, z: 0.0),
                    Point3D(x: 1.0, y: 0.0, z: 0.0),
                ],
                [
                    Point3D(x: 0.0, y: 1.0, z: 0.0),
                    Point3D(x: 1.0, y: 1.0, z: 0.0),
                ],
            ]
        ))
        let fixture = makeUntrimmedModel(surface: surface)

        let bounds = try DefaultFaceParameterBoundsResolver().bounds(
            for: fixture.faceID,
            in: fixture.model,
            tolerance: .standard
        )

        #expect(bounds.u == (try ScalarInterval(lower: 2.0, upper: 4.0)))
        #expect(bounds.v == (try ScalarInterval(lower: 3.0, upper: 7.0)))
    }

    @Test(.timeLimit(.minutes(1)))
    func untrimmedUnboundedSurfaceReportsTypedFailure() throws {
        let fixture = makeUntrimmedModel(
            surface: .plane(Plane3D(origin: .origin, normal: .unitZ))
        )

        do {
            _ = try DefaultFaceParameterBoundsResolver().bounds(
                for: fixture.faceID,
                in: fixture.model,
                tolerance: .standard
            )
            Issue.record("Expected an unbounded face to reject finite bounds.")
        } catch let error as KernelError {
            #expect(error.code == .invalidInput)
        }
    }

    private func makeTrimmedModel(
        surface: Surface3D,
        pcurves: [SurfaceParameterCurve]
    ) -> BoundsFixture {
        let surfaceID = SurfaceID()
        let faceID = FaceID()
        let loopID = LoopID()
        let coedges = pcurves.map {
            Coedge(edgeID: EdgeID(), surfaceParameterCurve: $0)
        }
        return BoundsFixture(
            faceID: faceID,
            model: BRepModel(
                geometry: GeometryStore(surfaces: [surfaceID: surface]),
                faces: [
                    faceID: Face(
                        id: faceID,
                        surfaceID: surfaceID,
                        loops: [loopID]
                    ),
                ],
                loops: [
                    loopID: Loop(
                        id: loopID,
                        role: .outer,
                        coedges: coedges
                    ),
                ]
            )
        )
    }

    private func makeUntrimmedModel(surface: Surface3D) -> BoundsFixture {
        let surfaceID = SurfaceID()
        let faceID = FaceID()
        return BoundsFixture(
            faceID: faceID,
            model: BRepModel(
                geometry: GeometryStore(surfaces: [surfaceID: surface]),
                faces: [
                    faceID: Face(
                        id: faceID,
                        surfaceID: surfaceID,
                        loops: []
                    ),
                ]
            )
        )
    }
}

private struct BoundsFixture {
    let faceID: FaceID
    let model: BRepModel
}

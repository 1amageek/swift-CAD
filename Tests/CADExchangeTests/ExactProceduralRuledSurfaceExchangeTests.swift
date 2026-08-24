import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import CADKernel
import Testing
@testable import CADExchange

@Suite("Exact procedural ruled surface exchange")
struct ExactProceduralRuledSurfaceExchangeTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func stepRoundTripUsesAnExactSameParameterNURBSRepresentation() throws {
        let fixture = try makeFixture()
        let sink = DataByteSink()
        try STEPExchange(tolerance: tolerance).write(
            brep: fixture.brep,
            units: .millimeters,
            to: sink
        )
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("B_SPLINE_SURFACE"))
        #expect(text.contains("TRIANGULATED_FACE_SET") == false)

        let imported = try STEPExchange(tolerance: tolerance).import(sink.bytes)
        try verify(
            imported: try #require(imported.brep),
            source: fixture.surface
        )
    }

    @Test(.timeLimit(.minutes(1)))
    func igesRoundTripUsesAnExactSameParameterNURBSRepresentation() throws {
        let fixture = try makeFixture()
        let sink = DataByteSink()
        try IGESExchange(tolerance: tolerance).write(
            brep: fixture.brep,
            units: .millimeters,
            to: sink
        )
        let text = try #require(String(data: sink.bytes, encoding: .utf8))
        #expect(text.contains("NURBSSRF"))
        #expect(text.contains("TRIANGULATED") == false)

        let imported = try IGESExchange(tolerance: tolerance).import(sink.bytes)
        try verify(
            imported: try #require(imported.brep),
            source: fixture.surface
        )
    }

    private func verify(
        imported: BRepModel,
        source: Surface3D
    ) throws {
        try imported.validate(level: .exact, tolerance: tolerance)
        #expect(imported.bodies.count == 1)
        #expect(imported.faces.count == 1)
        #expect(imported.edges.count == 4)
        #expect(imported.vertices.count == 4)
        let face = try #require(imported.faces.values.first)
        let importedSurface = try #require(
            imported.geometry.surfaces[face.surfaceID]
        )
        guard case .bSpline = importedSurface else {
            Issue.record("Official exchange must transfer a ruled surface as exact NURBS geometry.")
            return
        }
        for uIndex in 0...16 {
            let u = Double(uIndex) / 16.0
            for vIndex in 0...8 {
                let v = Double(vIndex) / 8.0
                let expected = try source.point(
                    u: u,
                    v: v,
                    tolerance: tolerance
                )
                let actual = try importedSurface.point(
                    u: u,
                    v: v,
                    tolerance: tolerance
                )
                #expect(
                    (actual - expected).length
                        <= tolerance.distance * 8.0
                )
            }
        }
    }

    private func makeFixture() throws -> (
        brep: BRepModel,
        surface: Surface3D
    ) {
        let start = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: 0.0, y: 0.0, z: 0.0),
                Point3D(x: 0.5, y: -0.15, z: 0.4),
                Point3D(x: 1.0, y: 0.0, z: 0.1),
            ],
            weights: [1.0, 0.45, 1.0]
        )
        let end = BSplineCurve3D(
            degree: 2,
            knots: [0.0, 0.0, 0.0, 1.0, 1.0, 1.0],
            controlPoints: [
                Point3D(x: -0.1, y: 1.0, z: 0.2),
                Point3D(x: 0.55, y: 1.2, z: 0.9),
                Point3D(x: 1.15, y: 1.0, z: -0.2),
            ],
            weights: [0.8, 1.8, 1.1]
        )
        let surface = Surface3D.procedural(.ruled(RuledSurface3D(
            startBoundary: .bSpline(start),
            endBoundary: .bSpline(end)
        )))
        let startStart = try start.point(at: 0.0, tolerance: tolerance)
        let startEnd = try start.point(at: 1.0, tolerance: tolerance)
        let endStart = try end.point(at: 0.0, tolerance: tolerance)
        let endEnd = try end.point(at: 1.0, tolerance: tolerance)
        let endRuling = try lineEdge(
            stableID: "ruled:end",
            start: startEnd,
            end: endEnd,
            parameterCurve: .constantU(
                u: 1.0,
                vStart: 0.0,
                vEnd: 1.0
            )
        )
        let startRuling = try lineEdge(
            stableID: "ruled:start",
            start: endStart,
            end: startStart,
            parameterCurve: .constantU(
                u: 0.0,
                vStart: 1.0,
                vEnd: 0.0
            )
        )
        let request = BRepSewingRequest(
            featureID: FeatureID(),
            bodyKind: .sheet,
            shells: [BRepSewingShell(
                stableID: "ruled:shell",
                patches: [BRepSewingFacePatch(
                    stableID: "ruled:face",
                    surface: surface,
                    orientation: .forward,
                    loops: [BRepSewingLoop(
                        stableID: "ruled:outer",
                        role: .outer,
                        edges: [
                            BRepSewingEdge(
                                stableID: "ruled:lower",
                                curve: .bSpline(start),
                                startParameter: 0.0,
                                endParameter: 1.0,
                                startPoint: startStart,
                                endPoint: startEnd,
                                surfaceParameterCurve: .constantV(
                                    v: 0.0,
                                    uStart: 0.0,
                                    uEnd: 1.0
                                )
                            ),
                            endRuling,
                            BRepSewingEdge(
                                stableID: "ruled:upper",
                                curve: .bSpline(end),
                                startParameter: 1.0,
                                endParameter: 0.0,
                                startPoint: endEnd,
                                endPoint: endStart,
                                surfaceParameterCurve: .constantV(
                                    v: 1.0,
                                    uStart: 1.0,
                                    uEnd: 0.0
                                )
                            ),
                            startRuling,
                        ]
                    )]
                )]
            )]
        )
        let sewn = try DefaultBRepSewer().sew(
            request,
            tolerance: tolerance
        )
        return (sewn.brep, surface)
    }

    private func lineEdge(
        stableID: String,
        start: Point3D,
        end: Point3D,
        parameterCurve: SurfaceParameterCurve
    ) throws -> BRepSewingEdge {
        let displacement = end - start
        return BRepSewingEdge(
            stableID: stableID,
            curve: .line(Line3D(
                origin: start,
                direction: try displacement.normalized(
                    tolerance: tolerance.distance
                )
            )),
            startParameter: 0.0,
            endParameter: displacement.length,
            startPoint: start,
            endPoint: end,
            surfaceParameterCurve: parameterCurve
        )
    }
}

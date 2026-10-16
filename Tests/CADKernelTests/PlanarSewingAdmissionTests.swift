import CADCore
import CADGeometry
import CADIR
import CADModeling
import CADTopology
import CADKernel
import Testing

@Suite("Planar sewing caller admission", .timeLimit(.minutes(1)))
struct PlanarSewingAdmissionTests {
    // This is the authored plane, line directions, native trims, UV polylines,
    // stable IDs and shell topology of the current PlanarSheetTestFixture.make.
    @inline(never)
    private func authoredRequest(featureID: FeatureID) throws -> BRepSewingRequest {
        let points = [
            Point3D(x: -0.020, y: -0.010, z: 0.0),
            Point3D(x: 0.020, y: -0.010, z: 0.0),
            Point3D(x: 0.020, y: 0.010, z: 0.0),
            Point3D(x: -0.020, y: 0.010, z: 0.0),
        ]
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let edges = try points.indices.map { index in
            let start = points[index]
            let end = points[(index + 1) % points.count]
            let delta = end - start
            let startUV = try surface.parameterProjection(of: start, tolerance: .standard)
            let endUV = try surface.parameterProjection(of: end, tolerance: .standard)
            return BRepSewingEdge(
                stableID: "planarSheet:edge:\(index)",
                curve: .line(Line3D(origin: start, direction: try delta.normalized(tolerance: 1.0e-9))),
                startParameter: 0.0, endParameter: delta.length,
                startPoint: start, endPoint: end,
                surfaceParameterCurve: .polyline([
                    SurfaceParameter(u: startUV.u, v: startUV.v),
                    SurfaceParameter(u: endUV.u, v: endUV.v),
                ]))
        }
        return BRepSewingRequest(featureID: featureID, bodyKind: .sheet,
            shells: [BRepSewingShell(stableID: "planarSheet:shell",
                patches: [BRepSewingFacePatch(stableID: "planarSheet:face",
                    surface: surface, orientation: .forward,
                    loops: [BRepSewingLoop(stableID: "planarSheet:outer", role: .outer, edges: edges)])])])
    }

    @Test
    func finiteWorkPublishesTheOriginalPlanarSheetGraph() throws {
        let request = try authoredRequest(featureID: FeatureID())
        let budget = try OriginalQueryBudget(workLimit: 262_144)
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
        let result = try DefaultBRepSewer().sew(request, tolerance: .standard, using: &execution)
        let model = result.brep
        #expect(model.bodies.count == 1 && model.shells.count == 1 && model.faces.count == 1)
        #expect(model.loops.count == 1 && model.edges.count == 4 && model.vertices.count == 4)
        #expect(model.geometry.curves.count == 4 && model.geometry.surfaces.count == 1)
        let body = try #require(model.bodies[result.bodyID])
        #expect(body.kind == .sheet && body.shellIDs.count == 1)
        let shellID = try #require(body.shellIDs.first)
        let shell = try #require(model.shells[shellID])
        #expect(shell.faceIDs.count == 1)
        let faceID = try #require(shell.faceIDs.first)
        let face = try #require(model.faces[faceID])
        #expect(face.orientation == .forward && face.loops.count == 1)
        guard case .plane(let plane) = try #require(model.geometry.surfaces[face.surfaceID]) else {
            Issue.record("Sewing replaced the authored plane family."); return
        }
        #expect(plane.origin == .origin && plane.normal == .unitZ && plane.uDirection == nil)
        let loopID = try #require(face.loops.first)
        let loop = try #require(model.loops[loopID])
        #expect(loop.role == .outer && loop.coedges.count == 4)
        let authored = request.shells[0].patches[0].loops[0].edges
        #expect(Set(loop.coedges.map(\.edgeID)).count == 4)
        for (use, original) in zip(loop.coedges, authored) {
            let edge = try #require(model.edges[use.edgeID])
            let trim = try #require(edge.trim)
            #expect(use.orientation == .forward)
            #expect(trim.startParameter == original.startParameter && trim.endParameter == original.endParameter)
            guard case .line(let emitted) = try #require(model.geometry.curves[edge.curveID]),
                case .line(let originalLine) = original.curve,
                case .polyline(let emittedUV) = try #require(use.surfaceParameterCurve),
                case .polyline(let originalUV) = original.surfaceParameterCurve else {
                Issue.record("Sewing replaced an authored line or two-point UV source."); return
            }
            #expect(emitted.origin == originalLine.origin && emitted.direction == originalLine.direction)
            #expect(emittedUV == originalUV)
            let start = try #require(model.vertices[edge.startVertexID])
            let end = try #require(model.vertices[edge.endVertexID])
            #expect(start.point == original.startPoint && end.point == original.endPoint)
        }
        let snapshot = budget.snapshot
        #expect(snapshot.work > 0 && snapshot.work <= 262_144 && snapshot.storageBytes > 0)
    }
}

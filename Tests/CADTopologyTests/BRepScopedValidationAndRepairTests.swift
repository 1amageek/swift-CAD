import CADCore
import CADGeometry
@testable import CADTopology
import Testing

@Suite("Scoped B-rep validation and explicit repair")
struct BRepScopedValidationAndRepairTests {
    private let tolerance = ModelingTolerance.standard

    @Test(.timeLimit(.minutes(1)))
    func selectedScopesCollectIndependentDiagnosticsWithoutMutation() throws {
        var fixture = makePlanarSheet()
        var loop = try #require(fixture.model.loops[fixture.loopID])
        loop.coedges = [
            loop.coedges[0],
            loop.coedges[2],
            Coedge(
                edgeID: loop.coedges[1].edgeID,
                orientation: loop.coedges[1].orientation,
                surfaceParameterCurve: nil
            ),
            loop.coedges[3],
        ]
        fixture.model.loops[fixture.loopID] = loop
        let original = fixture.model
        let validator = DefaultBRepTopologyValidator()

        let report = try validator.report(
            for: fixture.model,
            request: BRepValidationRequest(scopes: [.loops, .pcurves]),
            tolerance: tolerance
        )
        let references = try validator.report(
            for: fixture.model,
            request: BRepValidationRequest(scopes: [.references]),
            tolerance: tolerance
        )

        #expect(report.isValid == false)
        #expect(report.diagnostics.contains { $0.scope == .loops })
        #expect(report.diagnostics.contains { $0.scope == .pcurves })
        #expect(report.diagnostics.allSatisfy {
            $0.scope == .loops || $0.scope == .pcurves
        })
        #expect(references.isValid)
        #expect(fixture.model == original)
    }

    @Test(.timeLimit(.minutes(1)))
    func explicitRepairProducesAuditedValidTopology() throws {
        var fixture = makePlanarSheet()
        var body = try #require(fixture.model.bodies[fixture.bodyID])
        body.shellIDs.append(fixture.shellID)
        fixture.model.bodies[fixture.bodyID] = body

        var loop = try #require(fixture.model.loops[fixture.loopID])
        loop.coedges = [
            loop.coedges[2],
            loop.coedges[0],
            loop.coedges[3],
            loop.coedges[1],
        ]
        fixture.model.loops[fixture.loopID] = loop

        let orphanStartID = VertexID()
        let orphanEndID = VertexID()
        let orphanCurveID = CurveID()
        let orphanEdgeID = EdgeID()
        fixture.model.vertices[orphanStartID] = Vertex(
            id: orphanStartID,
            point: Point3D(x: 4.0, y: 0.0, z: 0.0)
        )
        fixture.model.vertices[orphanEndID] = Vertex(
            id: orphanEndID,
            point: Point3D(x: 5.0, y: 0.0, z: 0.0)
        )
        fixture.model.geometry.curves[orphanCurveID] = .line(Line3D(
            origin: Point3D(x: 4.0, y: 0.0, z: 0.0),
            direction: .unitX
        ))
        fixture.model.edges[orphanEdgeID] = Edge(
            id: orphanEdgeID,
            curveID: orphanCurveID,
            startVertexID: orphanStartID,
            endVertexID: orphanEndID,
            trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
        )
        let original = fixture.model

        let result = try DefaultBRepRepairer().repair(
            fixture.model,
            request: BRepRepairRequest(actions: [
                .deduplicateOwnershipReferences,
                .reorderAndOrientLoopCoedges,
                .pruneUnreferencedTopology,
            ]),
            tolerance: tolerance
        )

        #expect(result.before.isValid == false)
        #expect(result.after.isValid)
        #expect(result.diagnostics.isEmpty)
        #expect(Set(result.changes.map(\.action)) == Set(BRepRepairAction.allCases))
        #expect(result.model.edges[orphanEdgeID] == nil)
        #expect(result.model.vertices[orphanStartID] == nil)
        #expect(result.model.vertices[orphanEndID] == nil)
        #expect(result.model.geometry.curves[orphanCurveID] == nil)
        #expect(fixture.model == original)
        try result.model.validate(level: .exact, tolerance: tolerance)
    }

    @Test(.timeLimit(.minutes(1)))
    func repairActionOrderDoesNotChangeModelOrAuditLedger() throws {
        var fixture = makePlanarSheet()
        var body = try #require(fixture.model.bodies[fixture.bodyID])
        body.shellIDs.append(fixture.shellID)
        fixture.model.bodies[fixture.bodyID] = body

        var loop = try #require(fixture.model.loops[fixture.loopID])
        loop.coedges = [
            loop.coedges[2],
            loop.coedges[0],
            loop.coedges[3],
            loop.coedges[1],
        ]
        fixture.model.loops[fixture.loopID] = loop

        let orphanLoopID = LoopID()
        fixture.model.loops[orphanLoopID] = Loop(
            id: orphanLoopID,
            role: .outer,
            coedges: loop.coedges
        )
        let actions = BRepRepairAction.allCases
        let forward = try DefaultBRepRepairer().repair(
            fixture.model,
            request: BRepRepairRequest(actions: actions),
            tolerance: tolerance
        )
        let reversed = try DefaultBRepRepairer().repair(
            fixture.model,
            request: BRepRepairRequest(actions: Array(actions.reversed())),
            tolerance: tolerance
        )

        #expect(forward == reversed)
        #expect(forward.after.isValid)
        #expect(forward.diagnostics.isEmpty)
        #expect(forward.model.loops[orphanLoopID] == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func ambiguousRepairReturnsTypedDiagnosticWithoutGuessing() throws {
        var fixture = makePlanarSheet()
        var loop = try #require(fixture.model.loops[fixture.loopID])
        loop.coedges.append(loop.coedges[0])
        fixture.model.loops[fixture.loopID] = loop
        let original = fixture.model

        let result = try DefaultBRepRepairer().repair(
            fixture.model,
            request: BRepRepairRequest(
                actions: [.reorderAndOrientLoopCoedges],
                validationRequest: BRepValidationRequest(
                    scopes: [.loops, .pcurves, .orientation]
                )
            ),
            tolerance: tolerance
        )

        #expect(result.before.isValid == false)
        #expect(result.after.isValid == false)
        #expect(result.changes.isEmpty)
        #expect(result.diagnostics.isEmpty == false)
        #expect(result.diagnostics.allSatisfy {
            $0.action == .reorderAndOrientLoopCoedges
                && $0.code == .topologyFailure
        })
        #expect(result.model == original)
    }

    @Test(.timeLimit(.minutes(1)))
    func loopRepairSelectsTheUniqueMinimumOrientationChange() throws {
        var fixture = makePlanarSheet()
        let originalLoop = try #require(fixture.model.loops[fixture.loopID])
        let anchorIndex = try #require(originalLoop.coedges.indices.min { lhs, rhs in
            originalLoop.coedges[lhs].edgeID.description
                < originalLoop.coedges[rhs].edgeID.description
        })
        var damaged = originalLoop.coedges
        let anchor = damaged[anchorIndex]
        damaged[anchorIndex] = Coedge(
            edgeID: anchor.edgeID,
            orientation: anchor.orientation == .forward ? .reversed : .forward,
            surfaceParameterCurve: try anchor.surfaceParameterCurve?.reversed(
                tolerance: tolerance
            )
        )
        damaged = [damaged[2], damaged[0], damaged[3], damaged[1]]
        fixture.model.loops[fixture.loopID] = Loop(
            id: originalLoop.id,
            role: originalLoop.role,
            coedges: damaged
        )

        let result = try DefaultBRepRepairer().repair(
            fixture.model,
            request: BRepRepairRequest(actions: [.reorderAndOrientLoopCoedges]),
            tolerance: tolerance
        )
        let repairedLoop = try #require(result.model.loops[fixture.loopID])
        let expectedOrientations = Dictionary(uniqueKeysWithValues: originalLoop.coedges.map {
            ($0.edgeID, $0.orientation)
        })

        #expect(result.before.isValid == false)
        #expect(result.after.isValid)
        #expect(result.diagnostics.isEmpty)
        #expect(repairedLoop.coedges.allSatisfy {
            expectedOrientations[$0.edgeID] == $0.orientation
        })
    }

    @Test(.timeLimit(.minutes(1)))
    func repairRequestRejectsMissingAuditScopesAndDuplicateActions() throws {
        let missingScopes = BRepRepairRequest(
            actions: [.reorderAndOrientLoopCoedges],
            validationRequest: BRepValidationRequest(scopes: [.loops])
        )
        let duplicateActions = BRepRepairRequest(actions: [
            .deduplicateOwnershipReferences,
            .deduplicateOwnershipReferences,
        ])

        try expectInvalidInput {
            try missingScopes.validate(tolerance: tolerance)
        }
        try expectInvalidInput {
            try duplicateActions.validate(tolerance: tolerance)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func sharedOwnershipIsNotSilentlyClaimedByDeduplicationRepair() throws {
        var fixture = makePlanarSheet()
        let secondBodyID = BodyID()
        fixture.model.bodies[secondBodyID] = Body(
            id: secondBodyID,
            shellIDs: [fixture.shellID],
            kind: .sheet
        )
        let original = fixture.model

        let result = try DefaultBRepRepairer().repair(
            fixture.model,
            request: BRepRepairRequest(
                actions: [.deduplicateOwnershipReferences],
                validationRequest: BRepValidationRequest(scopes: [.references])
            ),
            tolerance: tolerance
        )

        #expect(result.before.isValid == false)
        #expect(result.after.isValid == false)
        #expect(result.changes.isEmpty)
        #expect(result.diagnostics.count == 1)
        #expect(result.diagnostics[0].action == .deduplicateOwnershipReferences)
        #expect(result.diagnostics[0].code == .topologyFailure)
        #expect(result.diagnostics[0].entityID == fixture.shellID.description)
        #expect(result.model == original)
    }

    private func makePlanarSheet() -> Fixture {
        let points = [
            Point3D(x: 0.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 0.0, z: 0.0),
            Point3D(x: 1.0, y: 1.0, z: 0.0),
            Point3D(x: 0.0, y: 1.0, z: 0.0),
        ]
        let vertexIDs = points.map { _ in VertexID() }
        let edgeIDs = points.map { _ in EdgeID() }
        let curveIDs = points.map { _ in CurveID() }
        let surfaceID = SurfaceID()
        let loopID = LoopID()
        let faceID = FaceID()
        let shellID = ShellID()
        let bodyID = BodyID()
        let directions = [
            Vector3D.unitX,
            Vector3D.unitY,
            -Vector3D.unitX,
            -Vector3D.unitY,
        ]
        let pcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0.0, uStart: 0.0, uEnd: 1.0),
            .constantU(u: 1.0, vStart: 0.0, vEnd: 1.0),
            .constantV(v: 1.0, uStart: 1.0, uEnd: 0.0),
            .constantU(u: 0.0, vStart: 1.0, vEnd: 0.0),
        ]
        let vertices = Dictionary(uniqueKeysWithValues: vertexIDs.enumerated().map { index, id in
            (id, Vertex(id: id, point: points[index]))
        })
        let curves = Dictionary(uniqueKeysWithValues: curveIDs.enumerated().map { index, id in
            (id, Curve3D.line(Line3D(origin: points[index], direction: directions[index])))
        })
        let edges = Dictionary(uniqueKeysWithValues: edgeIDs.enumerated().map { index, id in
            (id, Edge(
                id: id,
                curveID: curveIDs[index],
                startVertexID: vertexIDs[index],
                endVertexID: vertexIDs[(index + 1) % vertexIDs.count],
                trim: CurveTrim(startParameter: 0.0, endParameter: 1.0)
            ))
        })
        let coedges = edgeIDs.enumerated().map { index, edgeID in
            Coedge(
                edgeID: edgeID,
                surfaceParameterCurve: pcurves[index]
            )
        }
        let model = BRepModel(
            geometry: GeometryStore(
                curves: curves,
                surfaces: [
                    surfaceID: .plane(Plane3D(origin: .origin, normal: .unitZ)),
                ]
            ),
            bodies: [bodyID: Body(id: bodyID, shellIDs: [shellID], kind: .sheet)],
            shells: [shellID: Shell(id: shellID, faceIDs: [faceID])],
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
            loops: [loopID: Loop(id: loopID, role: .outer, coedges: coedges)],
            edges: edges,
            vertices: vertices
        )
        return Fixture(
            model: model,
            bodyID: bodyID,
            shellID: shellID,
            loopID: loopID
        )
    }

    private func expectInvalidInput(_ operation: () throws -> Void) throws {
        do {
            try operation()
            Issue.record("Expected a typed invalid-input failure.")
        } catch let error as KernelError {
            #expect(error.phase == .topology)
            #expect(error.code == .invalidInput)
        }
    }

    private struct Fixture {
        var model: BRepModel
        let bodyID: BodyID
        let shellID: ShellID
        let loopID: LoopID
    }
}

import CADCore
import CADGeometry
import CADTopology
import Synchronization
import Testing

@Suite("Explicit non-manifold topology")
struct NonManifoldTopologyTests {
    private let handler: any NonManifoldTopologyHandling = DefaultNonManifoldTopologyHandler()

    private func limits(records: Int = 1_000, work: Int = 20_000, diagnostics: Int = 100) throws -> TopologyRetentionLimits {
        try TopologyRetentionLimits(maximumTopologyRecords: records, maximumWork: work, maximumDiagnostics: diagnostics)
    }

    private func rejectBoth(_ retained: RetainedTopologyShape, requiring issue: (TopologyRetentionIssue) -> Bool) throws {
        for operation in [false, true] {
            do {
                if operation { _ = try handler.admitToBRepModeling(retained, tolerance: .standard, limits: limits()) }
                else { _ = try handler.admitToShapeOperations(retained, tolerance: .standard, limits: limits()) }
                Issue.record("Structurally defective topology was admitted.")
            } catch let error as TopologyRetentionError {
                guard case .modelingAdmissionRejected(let report) = error else { Issue.record("Unexpected resource failure."); return }
                let containsRequiredIssue = report.issues.contains(where: issue)
                #expect(containsRequiredIssue)
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func malformedRawSnapshotIsRetainedAndCallerMutationCannotChangeIt() throws {
        let vertex = VertexID()
        let missing = EdgeID()
        var model = BRepModel(vertices: [vertex: Vertex(id: vertex, point: .origin)])
        let source = Shape(root: .compound([.vertex(vertex), .edge(missing)]), model: model)
        let retained = try handler.retain(source, limits: limits())
        #expect(retained.root == source.root && retained.model == model)
        model.vertices.removeValue(forKey: vertex)
        var copy = retained.model
        copy.vertices[vertex] = Vertex(id: vertex, point: Point3D(x: 3, y: 4, z: 5))
        #expect(retained.model == source.model)
        #expect(retained.model.vertices[vertex]?.point == .origin)
        let report = try handler.diagnose(retained, limits: limits())
        #expect(report.issues.contains(.missingReference(owner: nil, target: .edge(missing))))
        try rejectBoth(retained) { $0 == .missingReference(owner: nil, target: .edge(missing)) }
    }

    @available(macOS 15.0, *)
    @Test(.timeLimit(.minutes(1)))
    func liveProviderIsCapturedExactlyOnce() throws {
        let first = VertexID(), second = VertexID()
        let model = BRepModel(vertices: [first: Vertex(id: first, point: .origin),
            second: Vertex(id: second, point: Point3D(x: 1, y: 0, z: 0))])
        let provider = SwitchingTopologyProvider(first: Shape(root: .vertex(first), model: model),
            second: Shape(root: .vertex(second), model: model))
        let retained = try handler.retain(provider, limits: limits())
        #expect(provider.count == 1)
        #expect(retained.root == .vertex(first))
        #expect(retained.model == model)
        _ = try handler.diagnose(retained, limits: limits())
        #expect(provider.count == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func threeFacesSharingAnEdgeRemainAvailableForDiagnosisAndAreRejected() throws {
        var fixture = PlanarTopologyFixture()
        let a = fixture.vertex(.origin), b = fixture.vertex(Point3D(x: 1, y: 0, z: 0))
        let c = fixture.vertex(Point3D(x: 0, y: 1, z: 0))
        let d = fixture.vertex(Point3D(x: 0, y: -1, z: 0))
        let e = fixture.vertex(Point3D(x: 1, y: 1, z: 0))
        try fixture.face([a, b, c]); try fixture.face([b, a, d]); try fixture.face([a, b, e])
        let shape = fixture.sheet()
        let shared = try #require(shape.model.edges.values.first { $0.startVertexID == a && $0.endVertexID == b })
        let retained = try handler.retain(shape, limits: limits())
        #expect(retained.model == shape.model)
        let expected = TopologyRetentionIssue.excessiveEdgeIncidence(edgeID: shared.id, useCount: 3)
        #expect(try handler.diagnose(retained, limits: limits()).issues.contains(expected))
        try rejectBoth(retained) { $0 == expected }
    }

    @Test(.timeLimit(.minutes(1)))
    func vertexOnlyFaceContactIsDiagnosedEvenWhenLegacyEdgeIncidenceIsValid() throws {
        var fixture = PlanarTopologyFixture()
        let origin = fixture.vertex(.origin)
        let a = fixture.vertex(Point3D(x: 1, y: 0, z: 0)), b = fixture.vertex(Point3D(x: 0, y: 1, z: 0))
        let c = fixture.vertex(Point3D(x: -1, y: 0, z: 0)), d = fixture.vertex(Point3D(x: 0, y: -1, z: 0))
        try fixture.face([origin, a, b]); try fixture.face([origin, c, d])
        let shape = fixture.sheet()
        let legacy = try DefaultBRepTopologyValidator().report(for: shape.model,
            request: .init(scopes: [.manifold]), tolerance: .standard)
        #expect(legacy.isValid)
        try shape.model.validate(level: .exact, tolerance: .standard)
        try DefaultShapeOperator().validate(shape, tolerance: .standard)
        let retained = try handler.retain(shape, limits: limits())
        let expected = TopologyRetentionIssue.nonManifoldVertexLink(vertexID: origin, componentCount: 2, branchCount: 0)
        #expect(try handler.diagnose(retained, limits: limits()).issues.contains(expected))
        try rejectBoth(retained) { $0 == expected }
    }

    @Test(.timeLimit(.minutes(1)))
    func manifoldTwoFaceFanAdmitsExactSheetAndCommonShapeOperations() throws {
        var fixture = PlanarTopologyFixture()
        let a = fixture.vertex(.origin), b = fixture.vertex(Point3D(x: 1, y: 0, z: 0))
        let c = fixture.vertex(Point3D(x: 0, y: 1, z: 0)), d = fixture.vertex(Point3D(x: 0, y: -1, z: 0))
        try fixture.face([a, b, c]); try fixture.face([b, a, d])
        let shape = fixture.sheet()
        let retained = try handler.retain(shape, limits: limits())
        #expect(!(try handler.diagnose(retained, limits: limits())).hasStructuralDefects)
        let exact = try handler.admitToBRepModeling(retained, tolerance: .standard, limits: limits())
        #expect(exact.model == shape.model && exact.validationLevel == .exact)
        let common = try handler.admitToShapeOperations(retained, tolerance: .standard, limits: limits())
        #expect(common.root == shape.root)
        try DefaultShapeOperator().validate(common, tolerance: .standard)
    }

    @Test(.timeLimit(.minutes(1)))
    func branchingWireIsRetainedButNeverAdmitted() throws {
        var fixture = PlanarTopologyFixture()
        let origin = fixture.vertex(.origin)
        let ends = [Point3D(x: 1, y: 0, z: 0), Point3D(x: 0, y: 1, z: 0), Point3D(x: -1, y: 0, z: 0)]
        var uses: [ShapeEdgeUse] = []
        for point in ends {
            let end = fixture.vertex(point)
            uses.append(ShapeEdgeUse(edgeID: try fixture.edge(origin, end).0))
        }
        let retained = try handler.retain(Shape(root: .wire(.init(edges: uses)), model: fixture.model), limits: limits())
        let report = try handler.diagnose(retained, limits: limits())
        #expect(report.issues.contains {
            if case .branchingWire(let vertex, let degree, _) = $0 { vertex == origin && degree == 3 } else { false }
        })
        try rejectBoth(retained) { if case .branchingWire = $0 { true } else { false } }
        let compound = try handler.retain(Shape(root: .compound(uses.map { .edge($0.edgeID) }), model: fixture.model), limits: limits())
        try rejectBoth(compound) { $0 == .branchingLooseEdges(vertexID: origin, degree: 3) }
    }

    @Test(.timeLimit(.minutes(1)))
    func commonDimensionalAdmissionDoesNotTurnStandaloneVerticesIntoBodies() throws {
        let id = VertexID()
        let source = Shape(root: .vertex(id), model: BRepModel(vertices: [id: Vertex(id: id, point: .origin)]))
        let retained = try handler.retain(source, limits: limits())
        #expect(!(try handler.diagnose(retained, limits: limits())).hasStructuralDefects)
        let admitted = try handler.admitToShapeOperations(retained, tolerance: .standard, limits: limits())
        #expect(admitted == source)
        do {
            _ = try handler.admitToBRepModeling(retained, tolerance: .standard, limits: limits())
            Issue.record("An unowned vertex became an exact body graph.")
        } catch let error as TopologyError {
            guard case .unreferencedTopology = error else { Issue.record("Unexpected body validation failure."); return }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func geometryFailureIsNotConvertedIntoCleanStructuralSuccess() throws {
        let vertexID = VertexID(), endID = VertexID(), curveID = CurveID(), edgeID = EdgeID()
        let model = BRepModel(geometry: GeometryStore(curves: [curveID: .line(Line3D(origin: .origin, direction: .unitX))]),
            edges: [edgeID: Edge(id: edgeID, curveID: curveID, startVertexID: vertexID, endVertexID: endID,
                trim: .init(startParameter: 0, endParameter: 1))],
            vertices: [vertexID: Vertex(id: vertexID, point: .origin), endID: Vertex(id: endID, point: Point3D(x: 2, y: 0, z: 0))])
        let retained = try handler.retain(Shape(root: .edge(edgeID), model: model), limits: limits())
        #expect(!(try handler.diagnose(retained, limits: limits())).hasStructuralDefects)
        #expect(throws: TopologyError.invalidTrim(edgeID)) {
            _ = try handler.admitToShapeOperations(retained, tolerance: .standard, limits: limits())
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func limitsRejectWithoutTruncatedReportsOrSilentPruning() throws {
        #expect(throws: TopologyRetentionError.invalidLimits) { _ = try limits(records: 0) }
        let a = VertexID(), b = VertexID()
        let source = Shape(root: .compound([.vertex(a), .vertex(b)]), model: BRepModel())
        let retained = try handler.retain(source, limits: limits())
        #expect(throws: TopologyRetentionError.resourceLimitExceeded(.work)) { _ = try handler.retain(source, limits: limits(work: 1)) }
        #expect(throws: TopologyRetentionError.resourceLimitExceeded(.diagnostics)) {
            _ = try handler.diagnose(retained, limits: limits(diagnostics: 1))
        }
        let model = BRepModel(vertices: [a: Vertex(id: a, point: .origin), b: Vertex(id: b, point: Point3D(x: 1, y: 0, z: 0))])
        #expect(throws: TopologyRetentionError.resourceLimitExceeded(.topologyRecords)) {
            _ = try handler.retain(Shape(root: .vertex(a), model: model), limits: limits(records: 1))
        }
        #expect(try handler.diagnose(retained, limits: limits()).issues.count == 2)
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationRejectsRetentionWithoutPublishingAValue() async throws {
        let source = Shape(root: .compound([]), model: BRepModel())
        let limits = try limits()
        let handler = handler
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try handler.retain(source, limits: limits)
        }
        do { _ = try await task.value; Issue.record("Cancelled retention succeeded.") }
        catch is CancellationError { }
    }
}

private struct PlanarTopologyFixture {
    var model = BRepModel()
    private let surfaceID = SurfaceID()
    private var faceIDs: [FaceID] = []

    init() { model.geometry.surfaces[surfaceID] = .plane(Plane3D(origin: .origin, normal: .unitZ)) }

    mutating func vertex(_ point: Point3D) -> VertexID {
        let id = VertexID()
        model.vertices[id] = Vertex(id: id, point: point)
        return id
    }

    mutating func edge(_ start: VertexID, _ end: VertexID) throws -> (EdgeID, Orientation) {
        if let existing = model.edges.values.first(where: {
            ($0.startVertexID == start && $0.endVertexID == end) || ($0.startVertexID == end && $0.endVertexID == start)
        }) { return (existing.id, existing.startVertexID == start ? .forward : .reversed) }
        let from = try #require(model.vertices[start]?.point), to = try #require(model.vertices[end]?.point)
        let curveID = CurveID(), edgeID = EdgeID()
        let displacement = to - from
        model.geometry.curves[curveID] = .line(Line3D(origin: from, direction: try displacement.normalized(tolerance: ModelingTolerance.standard.distance)))
        model.edges[edgeID] = Edge(id: edgeID, curveID: curveID, startVertexID: start, endVertexID: end,
            trim: CurveTrim(startParameter: 0, endParameter: displacement.length))
        return (edgeID, .forward)
    }

    mutating func face(_ vertices: [VertexID]) throws {
        let surface = try #require(model.geometry.surfaces[surfaceID])
        var coedges: [Coedge] = []
        for index in vertices.indices {
            let start = vertices[index], end = vertices[(index + 1) % vertices.count]
            let from = try surface.parameterProjection(of: #require(model.vertices[start]?.point), tolerance: .standard)
            let to = try surface.parameterProjection(of: #require(model.vertices[end]?.point), tolerance: .standard)
            let (id, orientation) = try edge(start, end)
            coedges.append(Coedge(edgeID: id, orientation: orientation, surfaceParameterCurve: .affine(
                origin: Point2D(x: from.u, y: from.v), direction: Point2D(x: to.u - from.u, y: to.v - from.v),
                startParameter: 0, endParameter: 1)))
        }
        let loopID = LoopID(), faceID = FaceID()
        model.loops[loopID] = Loop(id: loopID, coedges: coedges)
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
        faceIDs.append(faceID)
    }

    mutating func sheet() -> Shape {
        let shell = Shell(faceIDs: faceIDs)
        let body = Body(sheetShellIDs: [shell.id])
        model.shells[shell.id] = shell
        model.bodies[body.id] = body
        return Shape(root: .shell(shell.id), model: model)
    }
}

@available(macOS 15.0, *)
private final class SwitchingTopologyProvider: ShapeRepresenting {
    private let calls = Mutex(0)
    private let first: Shape
    private let second: Shape
    init(first: Shape, second: Shape) { self.first = first; self.second = second }
    var count: Int { calls.withLock { $0 } }
    func shapeSnapshot() -> Shape {
        calls.withLock { count in count += 1; return count == 1 ? first : second }
    }
}

import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections

/// A real sew/collapse/prune composition makes restored ledger ownership observable.
enum BRepRepairRollbackChecks {
    private struct Failure: Error { let message: String }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    private static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
            remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
    }

    static func originalDisplacementRollbackRestoresBothCandidateAndCollapsedLedger() throws {
        let square = BRepRepairExecutionFixture.polylineSquare()
        var input = square.model
        let tolerance = ModelingTolerance.standard, d = tolerance.distance * 0.75
        // Fixed IDs precede the generated square IDs, so A is the deterministic sew owner.
        let a = Vertex(id: VertexID(PortableIdentity128(high: 0, low: 1)), point: .origin)
        let b = Vertex(id: VertexID(PortableIdentity128(high: 0, low: 2)), point: .init(x: d, y: 0, z: 0))
        let c = Vertex(id: VertexID(PortableIdentity128(high: 0, low: 3)), point: .init(x: -d, y: 0, z: 0))
        let far = Vertex(id: VertexID(PortableIdentity128(high: 0, low: 4)), point: .init(x: 2, y: 0, z: 0))
        for vertex in [a, b, c, far] { input.vertices[vertex.id] = vertex }
        let shortCurveID = CurveID(PortableIdentity128(high: 0, low: 1))
        let longCurveID = CurveID(PortableIdentity128(high: 0, low: 2))
        // Unit-clamped affine Native controls retain the exact physical C->A segment.
        input.geometry.curves[shortCurveID] = .bSpline(.init(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [c.point, a.point], weights: [1, 1]))
        input.geometry.curves[longCurveID] = .line(.init(origin: b.point, direction: .unitX))
        let short = Edge(id: EdgeID(PortableIdentity128(high: 0, low: 1)), curveID: shortCurveID,
            startVertexID: c.id, endVertexID: a.id, trim: .init(startParameter: 0, endParameter: 1))
        let long = Edge(id: EdgeID(PortableIdentity128(high: 0, low: 2)), curveID: longCurveID,
            startVertexID: b.id, endVertexID: far.id, trim: .init(startParameter: 0, endParameter: 2 - d))
        input.edges[short.id] = short
        input.edges[long.id] = long
        let saved = input

        // Both invocations start cold and borrow exactly the same immutable authored input.
        let controlBudget = try OriginalQueryBudget(workLimit: 8_388_608)
        var controlExecution = try execution(controlBudget)
        let controlPort: any BRepRepairing = DefaultBRepRepairer()
        let control = try controlPort.repair(input,
            request: .init(actions: [.sewWireVertices, .pruneUnreferencedTopology]),
            tolerance: tolerance, using: &controlExecution)
        let fullBudget = try OriginalQueryBudget(workLimit: 8_388_608)
        var fullExecution = try execution(fullBudget)
        let fullPort: any BRepRepairing = DefaultBRepRepairer()
        let full = try fullPort.repair(input,
            request: .init(actions: [.sewWireVertices, .collapseSmallWireEdges, .pruneUnreferencedTopology]),
            tolerance: tolerance, using: &fullExecution)

        // Sew keeps the open C->A edge when merging both references would collapse it.
        // The long edge moves B->A, then a proposed C->A collapse would move it B->C:
        // 1.5*tolerance from its task-original source, despite each local move being 0.75*tolerance.
        let rollback = full.diagnostics.filter { $0.action == .collapseSmallWireEdges
            && $0.code == .topologyFailure && $0.message == "The candidate action exceeded cumulative displacement from the original source and was rolled back." }
        try require(rollback.count == 1 && full.diagnostics.count == 1 && control.diagnostics.isEmpty,
            "The real cumulative displacement candidate did not take exactly its outer collapse rollback.")
        try require(full.model == control.model && full.after.isValid && control.after.isValid,
            "Rollback failed to restore the accepted sew candidate before subsequent pruning.")
        try require(full.changes.allSatisfy { $0.action != .collapseSmallWireEdges }
            && full.changes.contains { $0.action == .sewWireVertices }
            && full.changes.contains { $0.action == .pruneUnreferencedTopology },
            "Rollback retained a rejected change or prevented the later real prune action.")
        // Prune deletes C. A stale pending collapse receipt retaining C would make its
        // audit return infinity and roll prune back too; successful prune tests ledger restoration.
        try require(full.model.edges[short.id] == nil && full.model.edges[long.id] == nil
            && full.model.vertices[b.id] == nil && full.model.vertices[c.id] == nil
            && full.model.vertices[far.id] == nil && full.model.geometry.curves[shortCurveID] == nil
            && full.model.geometry.curves[longCurveID] == nil && full.model.vertices[a.id]?.point == .origin,
            "The restored collapsed-source ledger prevented complete unreachable-tail pruning.")
        try require(full.model.edges.count == 4 && full.model.vertices.count == 4
            && full.model.loops[square.loopID]?.coedges.count == 4,
            "The accepted candidate lost the reachable original square.")
        try require(full.maximumDisplacement >= d && full.maximumDisplacement <= tolerance.distance
            && full.toleranceIncrease == 0, "Rollback widened the allowance or lost the accepted displacement audit.")
        try require(input == saved && input.edges[long.id]?.startVertexID == b.id
            && input.vertices[b.id]?.point == b.point && input.geometry.curves[shortCurveID] != nil,
            "An attempted action mutated the task-original source.")
        let controlSpent = controlBudget.snapshot, fullSpent = fullBudget.snapshot
        try require(controlBudget !== fullBudget && fullSpent.work > controlSpent.work
            && fullSpent.storageBytes > controlSpent.storageBytes,
            "The rolled-back candidate refunded its actually admitted work or storage.")
        try full.model.validate(level: .exact, tolerance: tolerance, using: &fullExecution)
        print("REPAIR_ROLLBACK controlWork=\(controlSpent.work) fullWork=\(fullSpent.work)")
    }
}

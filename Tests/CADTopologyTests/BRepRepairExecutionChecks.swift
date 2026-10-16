import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections
import Synchronization

/// Shared actual repair laws; Native and portable entry points invoke the same checks.
enum BRepRepairExecutionChecks {
    struct Failure: Error { let message: String }
    enum Injected: Error { case ordinaryEntry, sentinel }
    static let tolerance = ModelingTolerance.standard

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }
    static func execution(_ budget: OriginalQueryBudget, value: Int = 32, coefficient: Int = 32,
        source: Int = 16, subdivision: Int = 32) throws -> OriginalQueryExecution {
        .init(budget: budget, limits: try .init(maximumValueDepth: value, maximumCoefficientDepth: coefficient,
            remainingSourceDepth: source, maximumSubdivisionDepth: subdivision))
    }
    static func original(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return original(failure.originalError) }
        if let failure = error as? ExactScalarFailure, case .admissionRejected(let cause) = failure { return original(cause) }
        return error
    }
    static func repair(_ model: BRepModel, action: BRepRepairAction,
        using query: inout OriginalQueryExecution) throws -> BRepRepairResult {
        let provider: any BRepRepairing = DefaultBRepRepairer()
        let original = model
        let result = try provider.repair(model, request: .init(actions: [action]), tolerance: tolerance, using: &query)
        try require(model == original, "Repair changed the immutable input.")
        try require(result.model != original, "The requested action made no actual source change.")
        try require(result.after.isValid && result.diagnostics.isEmpty, "The changed repair did not publish a valid complete report.")
        try require(result.changes.contains { $0.action == action }, "The changed action is absent from its audit ledger.")
        try require(result.changes.allSatisfy { $0.action == action && $0.toleranceIncrease == 0
            && $0.maximumDisplacement <= tolerance.distance }, "The action escaped its unchanged displacement or action scope.")
        return result
    }
    static func query() throws -> OriginalQueryExecution { try execution(OriginalQueryBudget(workLimit: 8_388_608)) }

    static func ownership() throws {
        var f = BRepRepairExecutionFixture.polylineSquare()
        var body = f.model.bodies[f.bodyID]!
        body.topology = .sheet(shellIDs: [f.shellID, f.shellID]); f.model.bodies[f.bodyID] = body
        var shell = f.model.shells[f.shellID]!; shell.faceIDs += [f.faceID]; f.model.shells[f.shellID] = shell
        var face = f.model.faces[f.faceID]!; face.loops += [f.loopID]; f.model.faces[f.faceID] = face
        var a = try query()
        let r = try repair(f.model, action: .deduplicateOwnershipReferences, using: &a)
        try require(r.model.bodies[f.bodyID]?.shellIDs == [f.shellID]
            && r.model.shells[f.shellID]?.faceIDs == [f.faceID]
            && r.model.faces[f.faceID]?.loops == [f.loopID], "Ownership did not retain the original first occurrence.")
        try require(r.model.geometry == f.model.geometry && r.model.vertices == f.model.vertices,
            "Ownership cleanup changed geometry or vertex authority.")
    }
    static func loopOrdering() throws {
        var f = BRepRepairExecutionFixture.polylineSquare()
        let expected = f.model.loops[f.loopID]!.coedges
        var uses = expected
        uses[2].orientation = .reversed
        uses[2].surfaceParameterCurve = try uses[2].surfaceParameterCurve!.reversed(tolerance: tolerance)
        var loop = f.model.loops[f.loopID]!; loop.coedges = [uses[2], uses[0], uses[3], uses[1]]
        f.model.loops[f.loopID] = loop
        var a = try query()
        let r = try repair(f.model, action: .reorderAndOrientLoopCoedges, using: &a)
        let actual = r.model.loops[f.loopID]!.coedges
        try require(actual.count == 4 && expected.allSatisfy { use in actual.contains(use) },
            "Loop repair changed an original directed pcurve instead of restoring its cycle.")
        try require(r.model.edges == f.model.edges && r.model.geometry == f.model.geometry,
            "Loop ordering changed original support geometry.")
    }
    static func representation() throws {
        var f = BRepRepairExecutionFixture.polylineSquare()
        f.model.geometry.curves[f.curveIDs[0]] = nil
        var a = try query()
        let r = try repair(f.model, action: .reconstructCurveRepresentations, using: &a)
        guard case .surfaceLift(let source)? = r.model.geometry.curves[f.curveIDs[0]] else {
            throw Failure(message: "Missing curve repair did not publish its incident original lift.")
        }
        try require(source.surface == f.model.geometry.surfaces[f.surfaceID]
            && source.parameterCurve == f.model.loops[f.loopID]?.coedges[0].surfaceParameterCurve,
            "Reconstruction lost its retained support/chart binding.")
        try require(r.model.edges[f.edgeIDs[0]]?.trim == .init(startParameter: 0, endParameter: 1),
            "Reconstructed curve lost its normalized directed trim.")
        try require(r.changes.contains { $0.generatedEntityIDs.contains(f.curveIDs[0].description) },
            "Reconstructed source ID was omitted from the generated ledger.")
        // Missing inverse provenance is a distinct unsupported repair domain.
        var absent = BRepRepairExecutionFixture.polylineSquare()
        var loop = absent.model.loops[absent.loopID]!; loop.coedges[0].surfaceParameterCurve = nil
        absent.model.loops[absent.loopID] = loop
        let input = absent.model
        let unresolved = try DefaultBRepRepairer().repair(input,
            request: .init(actions: [.reconstructCurveRepresentations]), tolerance: tolerance, using: &a)
        try require(unresolved.model == input && !unresolved.after.isValid && !unresolved.diagnostics.isEmpty,
            "An unproved inverse chart became a successful reconstruction.")
    }
    static func wireSewing() throws {
        var f = BRepRepairExecutionFixture.polylineSquare()
        let old = f.vertexIDs[1], extra = VertexID()
        let p = f.model.vertices[old]!.point
        f.model.vertices[extra] = Vertex(id: extra, point: .init(x: p.x + tolerance.distance / 4, y: p.y, z: p.z))
        var edge = f.model.edges[f.edgeIDs[1]]!; edge.startVertexID = extra; f.model.edges[edge.id] = edge
        let owner = min(old, extra), removed = max(old, extra)
        var a = try query()
        let r = try repair(f.model, action: .sewWireVertices, using: &a)
        try require(r.model.edges[f.edgeIDs[0]]?.endVertexID == owner
            && r.model.edges[f.edgeIDs[1]]?.startVertexID == owner && r.model.vertices[removed] == nil,
            "Wire sewing did not retain the deterministic original vertex owner.")
        try require(r.changes.contains { $0.deletedEntityIDs.contains(removed.description)
            && $0.maximumDisplacement > 0 }, "Sewing lost its bounded displacement/deleted source record.")
    }
    static func duplicateWire() throws {
        var f = BRepRepairExecutionFixture.polylineSquare()
        let original = f.model.loops[f.loopID]!
        var loop = original; loop.coedges.insert(original.coedges[1], at: 2); f.model.loops[f.loopID] = loop
        var a = try query()
        let r = try repair(f.model, action: .removeDuplicateWireUses, using: &a)
        try require(r.model.loops[f.loopID] == original && r.model.geometry == f.model.geometry,
            "Duplicate use removal changed a directed original use or support.")
        var distinct = f.model
        loop = original
        var reversed = original.coedges[0]; reversed.orientation = .reversed
        reversed.surfaceParameterCurve = try reversed.surfaceParameterCurve!.reversed(tolerance: tolerance)
        loop.coedges.append(reversed); distinct.loops[f.loopID] = loop
        let saved = distinct
        let retained = try DefaultBRepRepairer().repair(distinct,
            request: .init(actions: [.removeDuplicateWireUses]), tolerance: tolerance, using: &a)
        try require(retained.model.loops[f.loopID]?.coedges == loop.coedges && retained.changes.isEmpty
            && !retained.after.isValid && !retained.diagnostics.isEmpty && distinct == saved,
            "A different reversed wire use was erased or its unresolved loop became valid.")
    }
    static func smallEdge() throws {
        var f = BRepRepairExecutionFixture.polylineSquare()
        let delta = tolerance.distance / 4, vertex = VertexID(), id = EdgeID(), curveID = CurveID()
        f.model.vertices[vertex] = Vertex(id: vertex, point: .init(x: delta, y: 0, z: 0))
        // A unit-clamped degree-one Native source has the exact original law P(f)=(delta*f,0,0).
        // Its physical image is unchanged, while its authored trim has positive unit width.
        f.model.geometry.curves[curveID] = .bSpline(.init(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [.origin, .init(x: delta, y: 0, z: 0)], weights: [1, 1]))
        f.model.edges[id] = Edge(id: id, curveID: curveID, startVertexID: f.vertexIDs[0],
            endVertexID: vertex, trim: .init(startParameter: 0, endParameter: 1))
        var edge = f.model.edges[f.edgeIDs[0]]!; edge.startVertexID = vertex
        edge.trim = .init(startParameter: delta, endParameter: 1); f.model.edges[edge.id] = edge
        var loop = f.model.loops[f.loopID]!
        loop.coedges[0].surfaceParameterCurve = .polyline([.init(u: delta, v: 0), .init(u: 1, v: 0)])
        loop.coedges.insert(Coedge(edgeID: id,
            surfaceParameterCurve: .polyline([.init(u: 0, v: 0), .init(u: delta, v: 0)])), at: 0)
        f.model.loops[f.loopID] = loop
        var a = try query()
        let authoredShort = f.model.edges[id]!, authoredCurve = f.model.geometry.curves[curveID]!
        try authoredShort.trim!.validate(on: authoredCurve, edgeID: id, tolerance: tolerance, using: &a)
        try require(try BRepEdgeGeometryClassifier().kind(of: authoredShort, in: f.model,
            tolerance: tolerance, using: &a) == .open,
            "The authored short Native interval is not an original open edge.")
        let r = try repair(f.model, action: .collapseSmallWireEdges, using: &a)
        try require(r.model.edges[id] == nil && r.model.vertices[vertex] == nil
            && r.model.geometry.curves[curveID] == nil && r.model.loops[f.loopID]?.coedges.count == 4,
            "Small edge collapse lost original curve/deleted vertex incidence.")
        try require(r.changes.contains { $0.deletedEntityIDs.contains(id.description)
            && $0.maximumDisplacement >= delta && $0.maximumDisplacement <= tolerance.distance },
            "Small edge removal omitted its whole original image displacement ledger.")
        let pole = try poleSheet(), host = pole.model.geometry.surfaces[pole.model.faces.values.first!.surfaceID]!
        let controls: [Curve3D] = [
            .bSpline(.init(degree: 1, knots: [0, 0, 0.5, 1, 1],
                controlPoints: [.origin, .init(x: delta, y: 0, z: 0), .origin])),
            .surfaceLift(.init(surface: host, parameterCurve: .constantV(v: 1, uStart: 0, uEnd: 1)))]
        for source in controls {
            let curveID = CurveID(), vertex = Vertex(point: try source.point(at: 0, tolerance: tolerance))
            let closed = Edge(curveID: curveID, startVertexID: vertex.id, endVertexID: vertex.id,
                trim: .init(startParameter: 0, endParameter: 1))
            let model = BRepModel(geometry: .init(curves: [curveID: source]), edges: [closed.id: closed], vertices: [vertex.id: vertex])
            let retained = try DefaultBRepRepairer().repair(model,
                request: .init(actions: [.collapseSmallWireEdges]), tolerance: tolerance, using: &a)
            try require(retained.model == model && retained.changes.isEmpty,
                "Small-edge repair erased closed or singular parameter incidence.")
        }
    }
    static func duplicateFace() throws {
        var cube = VolumeMomentLoopAdmissionChecks.cube().model
        let shellID = cube.shells.keys.first!, firstID = cube.shells[shellID]!.faceIDs[0]
        let original = cube.faces[firstID]!, loopID = LoopID(), faceID = FaceID()
        cube.loops[loopID] = Loop(id: loopID, role: .outer, coedges: cube.loops[original.loops[0]]!.coedges)
        cube.faces[faceID] = Face(id: faceID, surfaceID: original.surfaceID, loops: [loopID])
        var shell = cube.shells[shellID]!; shell.faceIDs.append(faceID); cube.shells[shellID] = shell
        var a = try query()
        let r = try repair(cube, action: .removeDuplicateFaces, using: &a)
        try require(r.model.faces.count == 6 && r.model.faces[faceID] == nil && r.model.loops[loopID] == nil
            && r.model.edges.count == 12 && r.model.vertices.count == 8,
            "Duplicate face removal failed to prune only its newly orphaned descendants.")
        try require(r.changes.contains { $0.deletedEntityIDs.contains(faceID.description) },
            "Duplicate face removal lost its deleted source identity.")
        var opposite = cube
        var reversedFace = opposite.faces[faceID]!; reversedFace.orientation = .reversed
        opposite.faces[faceID] = reversedFace
        let retained = try DefaultBRepRepairer().repair(opposite,
            request: .init(actions: [.removeDuplicateFaces]), tolerance: tolerance, using: &a)
        try require(retained.model == opposite && retained.model.faces[faceID] != nil
            && retained.changes.isEmpty && !retained.after.isValid && !retained.diagnostics.isEmpty,
            "Duplicate-face repair erased an opposite material orientation or declared its invalid incidence solved.")
    }
    static func shellSewing() throws {
        var cube = VolumeMomentLoopAdmissionChecks.cube().model
        let face = cube.faces.values.first!, loopID = face.loops[0]
        var loop = cube.loops[loopID]!
        let old = cube.edges[loop.coedges[0].edgeID]!, id = EdgeID()
        cube.edges[id] = Edge(id: id, curveID: old.curveID, startVertexID: old.startVertexID,
            endVertexID: old.endVertexID, trim: old.trim)
        loop.coedges[0].edgeID = id; cube.loops[loopID] = loop
        var a = try query()
        let r = try repair(cube, action: .sewShellEdges, using: &a)
        try require(r.model.edges.count == 12 && r.model.loops.values.flatMap { $0.coedges }
            .filter { $0.edgeID == (r.model.edges[old.id] == nil ? id : old.id) }.count == 2,
            "Shell sewing did not restore one canonical two-use edge.")
        try require(r.model.vertices == cube.vertices && r.model.geometry == cube.geometry,
            "Shell sewing changed original support or vertices.")
    }
    static func flipFace(_ id: FaceID, in model: inout BRepModel) throws {
        var face = model.faces[id]!
        for loopID in face.loops {
            var loop = model.loops[loopID]!
            loop.coedges = try loop.coedges.reversed().map { use in
                Coedge(edgeID: use.edgeID, orientation: use.orientation == .forward ? .reversed : .forward,
                    surfaceParameterCurve: try use.surfaceParameterCurve!.reversed(tolerance: tolerance)) }
            model.loops[loopID] = loop
        }
        face.orientation = face.orientation == .forward ? .reversed : .forward
        model.faces[id] = face
    }
    static func shellOrientation() throws {
        var cube = VolumeMomentLoopAdmissionChecks.cube().model
        let original = cube, id = cube.faces.keys.sorted().last!
        try flipFace(id, in: &cube)
        var a = try query()
        let r = try repair(cube, action: .orientShellFaces, using: &a)
        try require(r.model == original, "Shell orientation failed to restore the unique one-face reversal.")
    }
    static func solidOrientation() throws {
        var cube = VolumeMomentLoopAdmissionChecks.cube().model
        let original = cube, shellID = cube.shells.keys.first!
        for id in cube.faces.keys.sorted() { try flipFace(id, in: &cube) }
        var shell = cube.shells[shellID]!; shell.orientation = .reversed; cube.shells[shellID] = shell
        var a = try query()
        let r = try repair(cube, action: .orientSolidComponents, using: &a)
        try require(r.model == original && r.changes.contains { $0.scope == .volume },
            "Solid repair did not restore both the explicit shell role and signed boundary direction.")
        let volume = try r.model.volume(tolerance: tolerance, using: &a)
        try require(abs(volume - 1) <= tolerance.distance,
            "The repaired unit cube lacks its independently known positive volume.")
        var rational = try execution(OriginalQueryBudget(workLimit: 8_388_608), value: 0, coefficient: 0)
        let rationalResult = try repair(cube, action: .orientSolidComponents, using: &rational)
        try require(rationalResult.model == original && rationalResult.changes.contains { $0.scope == .volume }
            && rational.effectiveLimits.maximumValueDepth == 0 && rational.effectiveLimits.maximumCoefficientDepth == 0
            && rational.valueDepth == 0 && rational.coefficientDepth == 0,
            "The rational cube's local producer policy widened an independent caller axis.")
    }
    static func pruning() throws {
        var f = BRepRepairExecutionFixture.polylineSquare()
        let vertex = VertexID(), other = VertexID(), curve = CurveID(), edge = EdgeID()
        f.model.vertices[vertex] = Vertex(id: vertex, point: .init(x: 4, y: 0, z: 0))
        f.model.vertices[other] = Vertex(id: other, point: .init(x: 5, y: 0, z: 0))
        f.model.geometry.curves[curve] = .line(.init(origin: .init(x: 4, y: 0, z: 0), direction: .unitX))
        f.model.edges[edge] = Edge(id: edge, curveID: curve, startVertexID: vertex,
            endVertexID: other, trim: .init(startParameter: 0, endParameter: 1))
        var a = try query()
        let r = try repair(f.model, action: .pruneUnreferencedTopology, using: &a)
        try require(r.model.edges[edge] == nil && r.model.vertices[vertex] == nil
            && r.model.vertices[other] == nil && r.model.geometry.curves[curve] == nil,
            "Pruning retained unreachable geometry or removed reachable ownership.")
        try require(f.edgeIDs.allSatisfy { r.model.edges[$0] == f.model.edges[$0] }
            && r.model.bodies == f.model.bodies && r.model.faces == f.model.faces,
            "Pruning changed the reachable source graph.")
        let deleted = r.changes.flatMap { $0.deletedEntityIDs }
        try require(deleted.contains("edge:" + edge.description) && deleted.contains("curve:" + curve.description),
            "Pruning omitted original kind-qualified deleted source identities.")
    }

    static func poleSheet() throws -> (model: BRepModel, loop: LoopID, pole: VertexID) {
        let host = Surface3D.bSpline(.init(uDegree: 1, vDegree: 1, uKnots: [0, 0, 1, 1],
            vKnots: [0, 0, 1, 1], controlPoints: [
                [.init(x: -1, y: 0, z: 0), .init(x: 1, y: 0, z: 0)],
                [.init(x: 0, y: 0, z: 1), .init(x: 0, y: 0, z: 1)]], weights: [[1, 1], [1, 1]]))
        let charts: [SurfaceParameterCurve] = [.constantV(v: 0, uStart: 0, uEnd: 1),
            .constantU(u: 1, vStart: 0, vEnd: 1), .constantU(u: 0, vStart: 1, vEnd: 0)]
        let points = [Point3D(x: -1, y: 0, z: 0), .init(x: 1, y: 0, z: 0), .init(x: 0, y: 0, z: 1)]
        let vertices = points.map { Vertex(point: $0) }
        var model = BRepModel(), uses: [Coedge] = []
        for vertex in vertices { model.vertices[vertex.id] = vertex }
        for i in charts.indices {
            let curveID = CurveID(), edgeID = EdgeID()
            model.geometry.curves[curveID] = .surfaceLift(.init(surface: host, parameterCurve: charts[i]))
            model.edges[edgeID] = Edge(id: edgeID, curveID: curveID, startVertexID: vertices[i].id,
                endVertexID: vertices[(i + 1) % 3].id, trim: .init(startParameter: 0, endParameter: 1))
            uses.append(Coedge(edgeID: edgeID, surfaceParameterCurve: charts[i]))
        }
        let surfaceID = SurfaceID(), loopID = LoopID(), faceID = FaceID(), shellID = ShellID(), bodyID = BodyID()
        model.geometry.surfaces[surfaceID] = host
        model.loops[loopID] = Loop(id: loopID, role: .outer, coedges: uses)
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
        model.shells[shellID] = Shell(id: shellID, faceIDs: [faceID])
        model.bodies[bodyID] = Body(id: bodyID, sheetShellIDs: [shellID])
        return (model, loopID, vertices[2].id)
    }
    static func singularBoundary() throws {
        let input = try poleSheet()
        var a = try query()
        let r = try repair(input.model, action: .restoreSingularBoundaryUses, using: &a)
        let created = r.model.edges.values.filter { input.model.edges[$0.id] == nil }
        try require(created.count == 1 && r.model.loops[input.loop]?.coedges.count == 4,
            "The omitted collapsed chart use was not restored exactly once.")
        let edge = created[0]
        try require(edge.startVertexID == input.pole && edge.endVertexID == input.pole
            && edge.trim == .init(startParameter: 0, endParameter: 1),
            "The restored pole use lost its same-vertex parameter incidence.")
        guard case .surfaceLift(let source)? = r.model.geometry.curves[edge.curveID],
            case .constantV(let v, let start, let end) = source.parameterCurve else {
            throw Failure(message: "The new singular edge lost its original constant-V source lift.")
        }
        try require(v == 1 && start == 1 && end == 0 && r.model.vertices == input.model.vertices,
            "Restoring a UV pole gap moved source geometry or collapsed its nonzero UV extent.")
    }
    static func periodicCharts() throws {
        let period = Double.pi * 2
        let host = Surface3D.cylinder(.init(origin: .origin, axis: .unitZ, radius: 1))
        let charts: [SurfaceParameterCurve] = [
            .constantV(v: 0, uStart: period - 0.25, uEnd: period + 0.25),
            .constantU(u: 0.25, vStart: 0, vEnd: 1),
            .constantV(v: 1, uStart: 0.25, uEnd: -0.25),
            .constantU(u: -0.25, vStart: 1, vEnd: 0)]
        let parameters = [SurfaceParameter(u: period - 0.25, v: 0), .init(u: period + 0.25, v: 0),
            .init(u: period + 0.25, v: 1), .init(u: period - 0.25, v: 1)]
        var model = BRepModel(), vertices: [Vertex] = [], uses: [Coedge] = []
        for uv in parameters { vertices.append(Vertex(point: try host.point(u: uv.u, v: uv.v, tolerance: tolerance))) }
        for vertex in vertices { model.vertices[vertex.id] = vertex }
        for i in charts.indices {
            let curveID = CurveID(), edgeID = EdgeID()
            model.geometry.curves[curveID] = .surfaceLift(.init(surface: host, parameterCurve: charts[i]))
            model.edges[edgeID] = Edge(id: edgeID, curveID: curveID, startVertexID: vertices[i].id,
                endVertexID: vertices[(i + 1) % 4].id, trim: .init(startParameter: 0, endParameter: 1))
            uses.append(Coedge(edgeID: edgeID, surfaceParameterCurve: charts[i]))
        }
        let surfaceID = SurfaceID(), loopID = LoopID(), faceID = FaceID(), shellID = ShellID(), bodyID = BodyID()
        model.geometry.surfaces[surfaceID] = host
        model.loops[loopID] = Loop(id: loopID, role: .outer, coedges: uses)
        model.faces[faceID] = Face(id: faceID, surfaceID: surfaceID, loops: [loopID])
        model.shells[shellID] = Shell(id: shellID, faceIDs: [faceID])
        model.bodies[bodyID] = Body(id: bodyID, sheetShellIDs: [shellID])
        var a = try query()
        let r = try repair(model, action: .restorePeriodicCharts, using: &a)
        let restored = r.model.loops[loopID]!.coedges
        try require(restored[0] == uses[0] && restored.count == 4
            && r.model.edges == model.edges && r.model.vertices == model.vertices && r.model.geometry == model.geometry,
            "Periodic repair changed spatial source or the anchor chart.")
        for i in 1...3 {
            guard case .periodicTranslation(let base, let u, let v)? = restored[i].surfaceParameterCurve else {
                throw Failure(message: "Periodic repair did not retain its original chart and exact period translation.")
            }
            try require(base == charts[i] && u == period && v == 0,
                "Periodic restoration used a different law or a nonperiod shift.")
        }
    }

    static func requestScopes() throws {
        let cases: [(BRepRepairAction, [TopologyValidationScope])] = [
            (.deduplicateOwnershipReferences, [.references]),
            (.reorderAndOrientLoopCoedges, [.loops, .pcurves, .orientation]),
            (.reconstructCurveRepresentations, [.references, .pcurves]),
            (.sewWireVertices, [.references, .loops]), (.removeDuplicateWireUses, [.references, .loops]),
            (.collapseSmallWireEdges, [.references, .loops]), (.restorePeriodicCharts, [.loops, .pcurves]),
            (.restoreSingularBoundaryUses, [.references, .loops, .pcurves]),
            (.removeDuplicateFaces, [.references, .orientation, .manifold, .watertight]),
            (.sewShellEdges, [.references, .orientation, .manifold, .watertight]),
            (.orientShellFaces, [.orientation, .manifold, .watertight]),
            (.orientSolidComponents, [.references, .orientation, .manifold, .watertight, .volume]),
            (.pruneUnreferencedTopology, [.references])]
        for (action, required) in cases {
            var a = try query()
            try BRepRepairRequest(actions: [action], validationRequest: .init(scopes: required))
                .validate(tolerance: tolerance, using: &a)
            for omitted in required {
                let remaining = TopologyValidationScope.allCases.filter { $0 != omitted }
                do {
                    try BRepRepairRequest(actions: [action], validationRequest: .init(scopes: remaining))
                        .validate(tolerance: tolerance, using: &a)
                } catch {
                    guard let failure = original(error) as? KernelError, failure.phase == .topology,
                        failure.code == .invalidInput else { throw error }
                    continue
                }
                throw Failure(message: "A public repair request omitted a required validation scope.")
            }
        }
    }
    static func ownershipDefect() -> BRepRepairExecutionFixture.Sheet {
        var f = BRepRepairExecutionFixture.polylineSquare()
        var body = f.model.bodies[f.bodyID]!
        body.topology = .sheet(shellIDs: [f.shellID, f.shellID]); f.model.bodies[f.bodyID] = body
        return f
    }
    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func check() throws(ExactScalarFailure) {
            let ordinal = state.withLock { $0 += 1; return $0 }
            if ordinal == stop { throw .cancelled }
        }
    }
    static func resourceBoundariesAndIndependentAxes() throws {
        var f = BRepRepairExecutionFixture.polylineTriangle()
        var body = f.model.bodies[f.bodyID]!
        body.topology = .sheet(shellIDs: [f.shellID, f.shellID]); f.model.bodies[f.bodyID] = body
        let input = f.model
        func run(_ budget: OriginalQueryBudget, value: Int = 32, coefficient: Int = 32) throws -> BRepRepairResult {
            var a = try execution(budget, value: value, coefficient: coefficient)
            try a.consumeWork(11)
            let result = try repair(input, action: .deduplicateOwnershipReferences, using: &a)
            try require(a.effectiveLimits.maximumValueDepth == value && a.effectiveLimits.maximumCoefficientDepth == coefficient
                && a.valueDepth <= value && a.coefficientDepth <= coefficient,
                "A repair local policy widened an independent incoming algebra axis.")
            return result
        }
        let measured = try OriginalQueryBudget()
        let expected = try run(measured), n = measured.snapshot
        let exact = try OriginalQueryBudget(workLimit: n.work, storageByteLimit: n.storageBytes)
        let repeated = try run(exact)
        try require(repeated == expected && exact.snapshot.work == n.work && exact.snapshot.storageBytes == n.storageBytes,
            "The retained input's exact cumulative repair boundary changed.")
        for resource in [ExactResource.work, .storage] {
            let budget = try OriginalQueryBudget(workLimit: resource == .work ? n.work - 1 : nil,
                storageByteLimit: resource == .storage ? n.storageBytes - 1 : nil)
            do { _ = try run(budget) }
            catch {
                guard let failure = original(error) as? ExactScalarFailure,
                    case .resourceLimit(let actual) = failure, actual == resource else { throw error }
                try require(budget.snapshot.work <= (resource == .work ? n.work - 1 : n.work)
                    && budget.snapshot.storageBytes <= (resource == .storage ? n.storageBytes - 1 : n.storageBytes),
                    "A rejected repair debit was committed or refunded.")
                continue
            }
            throw Failure(message: "An N-1 repair invocation published a result.")
        }
        for (v, c) in [(0, 32), (32, 0), (0, 0)] { _ = try run(OriginalQueryBudget(), value: v, coefficient: c) }
        print("REPAIR_N work=\(n.work) bytes=\(n.storageBytes)")
    }
    static func cancellationAndLifetime() throws {
        var f = BRepRepairExecutionFixture.polylineTriangle()
        var body = f.model.bodies[f.bodyID]!
        body.topology = .sheet(shellIDs: [f.shellID, f.shellID]); f.model.bodies[f.bodyID] = body
        let observed = Checkpoints()
        var measuring = try execution(OriginalQueryBudget(checkpoint: { try observed.check() }))
        _ = try repair(f.model, action: .deduplicateOwnershipReferences, using: &measuring)
        let n = measuring.budget.snapshot
        try require(observed.count > 2, "Repair exposed no interior cancellation checkpoint.")
        for stop in [1, observed.count / 2, observed.count] {
            let observer = Checkpoints(stop: stop)
            let budget = try OriginalQueryBudget(checkpoint: { try observer.check() })
            var a = try execution(budget)
            do { _ = try repair(f.model, action: .deduplicateOwnershipReferences, using: &a) }
            catch {
                if let failure = original(error) as? ExactScalarFailure, case .cancelled = failure {
                    try require(observer.count == stop && budget.snapshot.work <= n.work
                        && budget.snapshot.storageBytes <= n.storageBytes,
                        "Repair cancellation lost its original checkpoint or cumulative spending.")
                    if stop == 1 { try require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0,
                        "Entry cancellation spent work or bytes.") }
                    else { try require(budget.snapshot.work > 0, "In-progress cancellation refunded its admitted work.") }
                    continue
                }
                throw error
            }
            throw Failure(message: "A cancelled repair invocation published a result.")
        }
        func retained() throws -> BRepRepairResult {
            var source = f.model
            var a = try query()
            let result = try repair(source, action: .deduplicateOwnershipReferences, using: &a)
            let id = f.vertexIDs[0]
            source.vertices[id] = Vertex(id: id, point: .init(x: 99, y: 0, z: 0))
            source.loops[f.loopID] = nil
            try require(result.model.vertices[id]?.point == .origin && result.model.loops[f.loopID] != nil,
                "Authored source mutation changed the published repaired model.")
            return result
        }
        let result = try retained()
        try require(result.after.isValid && result.model.bodies[f.bodyID]?.shellIDs == [f.shellID],
            "The published repair lost its source owner after the execution ended.")
    }
    private final class ValidationTrace: Sendable {
        struct State: Sendable {
            var calls = 0
            var work: [Int] = []
            var effective: [OriginalQueryExecutionLimits] = []
            var ambient: [OriginalQueryExecutionLimits] = []
            var owner: OriginalQueryBudget?
            var sameOwner = true
        }
        private let state = Mutex(State())
        let budget: OriginalQueryBudget?
        let failAt: Int?
        let overflow: Bool
        init(budget: OriginalQueryBudget? = nil, failAt: Int? = nil, overflow: Bool = false) {
            self.budget = budget; self.failAt = failAt; self.overflow = overflow
        }
        var snapshot: State { state.withLock { $0 } }
        func observe(_ actual: OriginalQueryBudget, effective: OriginalQueryExecutionLimits,
            ambient: OriginalQueryExecutionLimits) -> Int {
            let work = actual.snapshot.work
            return state.withLock {
                let expected = budget ?? $0.owner
                if let expected { $0.sameOwner = $0.sameOwner && actual === expected }
                else { $0.owner = actual }
                $0.calls += 1; $0.work.append(work); $0.effective.append(effective); $0.ambient.append(ambient)
                return $0.calls
            }
        }
    }
    private struct Validator: BRepTopologyValidating {
        let trace: ValidationTrace
        func report(for model: BRepModel, request: BRepValidationRequest,
            tolerance: ModelingTolerance) throws -> TopologyValidationReport { throw Injected.ordinaryEntry }
        func report(for model: BRepModel, request: BRepValidationRequest, tolerance: ModelingTolerance,
            using a: inout OriginalQueryExecution) throws -> TopologyValidationReport {
            let call = trace.observe(a.budget, effective: a.effectiveLimits, ambient: a.limits)
            try a.consumeWork(7)
            if trace.overflow { try a.retainStorage(count: Int.max, stride: 2) }
            if call == trace.failAt { throw Injected.sentinel }
            return try DefaultBRepTopologyValidator().report(for: model, request: request, tolerance: tolerance, using: &a)
        }
    }
    static func injectedWitnessAndAbortPreserveOriginalCause() throws {
        let input = ownershipDefect().model, saved = input, budget = try OriginalQueryBudget()
        let trace = ValidationTrace(budget: budget)
        var a = try execution(budget)
        let port: any BRepRepairing = DefaultBRepRepairer(validator: Validator(trace: trace))
        let r = try port.repair(input, request: .init(actions: [.deduplicateOwnershipReferences]),
            tolerance: tolerance, using: &a)
        let log = trace.snapshot
        try require(r.after.isValid && log.calls == 2 && log.sameOwner && log.work[1] > log.work[0]
            && input == saved, "Before/after validation escaped the direct witness or caller owner.")
        let ordinaryTrace = ValidationTrace()
        let ordinary = try DefaultBRepRepairer(validator: Validator(trace: ordinaryTrace))
            .repair(input, request: .init(actions: [.deduplicateOwnershipReferences]), tolerance: tolerance)
        let ordinaryLog = ordinaryTrace.snapshot
        try require(ordinary.after.isValid && ordinaryLog.calls == 2 && ordinaryLog.sameOwner
            && ordinaryLog.ambient.allSatisfy { $0.maximumValueDepth == Int.max
                && $0.maximumCoefficientDepth == Int.max && $0.remainingSourceDepth == Int.max }
            && ordinaryLog.effective.allSatisfy { $0.maximumValueDepth == 32
                && $0.maximumCoefficientDepth == 32 && $0.remainingSourceDepth == 16
                && $0.maximumSubdivisionDepth == 32 },
            "The ordinary repair root or its existing local Topology phase policy changed.")
        for failAt in [1, 2] {
            let failedBudget = try OriginalQueryBudget(), observer = ValidationTrace(budget: failedBudget, failAt: failAt)
            var pending = try execution(failedBudget)
            do {
                _ = try DefaultBRepRepairer(validator: Validator(trace: observer)).repair(input,
                    request: .init(actions: [.deduplicateOwnershipReferences]), tolerance: tolerance, using: &pending)
            } catch {
                guard let cause = original(error) as? Injected, case .sentinel = cause else { throw error }
                try require(input == saved && failedBudget.snapshot.work > 0 && observer.snapshot.calls == failAt,
                    "An aborted repair changed input, lost its cause, or refunded admitted work.")
                continue
            }
            throw Failure(message: "An injected validation failure became a repaired result.")
        }
        let overflowBudget = try OriginalQueryBudget(), observer = ValidationTrace(budget: overflowBudget, overflow: true)
        var pending = try execution(overflowBudget)
        do {
            _ = try DefaultBRepRepairer(validator: Validator(trace: observer)).repair(input,
                request: .init(actions: [.deduplicateOwnershipReferences]), tolerance: tolerance, using: &pending)
        } catch {
            guard let cause = original(error) as? ExactScalarFailure, case .countOverflow = cause else { throw error }
            try require(input == saved && overflowBudget.snapshot.work > 0,
                "An overflowed injected admission changed or refunded the original invocation.")
            return
        }
        throw Failure(message: "Overflowed storage admission published a repair result.")
    }

    static func cumulativeCollapseAndAbortRetainTheTaskOriginalSource() throws {
        var square = BRepRepairExecutionFixture.polylineSquare()
        let d = tolerance.distance * 0.6
        let a = square.model.vertices[square.vertexIDs[0]]!
        let b = Vertex(id: VertexID(PortableIdentity128(high: 0, low: 11)), point: .init(x: d, y: 0, z: 0))
        let c = Vertex(id: VertexID(PortableIdentity128(high: 0, low: 12)), point: .init(x: d * 2, y: 0, z: 0))
        let curve1 = CurveID(), curve2 = CurveID()
        let first = Edge(id: EdgeID(PortableIdentity128(high: 0, low: 1)), curveID: curve1,
            startVertexID: a.id, endVertexID: b.id, trim: .init(startParameter: 0, endParameter: 1))
        let second = Edge(id: EdgeID(PortableIdentity128(high: 0, low: 2)), curveID: curve2,
            startVertexID: b.id, endVertexID: c.id, trim: .init(startParameter: 0, endParameter: 1))
        // These exact affine Native laws preserve the two physical short segments.
        let firstCurve = Curve3D.bSpline(.init(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [a.point, b.point], weights: [1, 1]))
        let secondCurve = Curve3D.bSpline(.init(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [b.point, c.point], weights: [1, 1]))
        square.model.vertices[b.id] = b; square.model.vertices[c.id] = c
        square.model.geometry.curves[curve1] = firstCurve; square.model.geometry.curves[curve2] = secondCurve
        square.model.edges[first.id] = first; square.model.edges[second.id] = second
        var remainder = square.model.edges[square.edgeIDs[0]]!
        remainder.startVertexID = c.id
        remainder.trim = .init(startParameter: d * 2, endParameter: 1)
        square.model.edges[remainder.id] = remainder
        var loop = square.model.loops[square.loopID]!
        loop.coedges[0].surfaceParameterCurve = .polyline([.init(u: d * 2, v: 0), .init(u: 1, v: 0)])
        loop.coedges.insert(Coedge(edgeID: second.id,
            surfaceParameterCurve: .polyline([.init(u: d, v: 0), .init(u: d * 2, v: 0)])), at: 0)
        loop.coedges.insert(Coedge(edgeID: first.id,
            surfaceParameterCurve: .polyline([.init(u: 0, v: 0), .init(u: d, v: 0)])), at: 0)
        square.model.loops[square.loopID] = loop
        let input = square.model
        let request = BRepRepairRequest(actions: [.collapseSmallWireEdges, .orientShellFaces])
        let saved = input
        var query = try self.query()
        for edge in [first, second] {
            let curve = input.geometry.curves[edge.curveID]!
            try edge.trim!.validate(on: curve, edgeID: edge.id, tolerance: tolerance, using: &query)
            try require(try BRepEdgeGeometryClassifier().kind(of: edge, in: input,
                tolerance: tolerance, using: &query) == .open,
                "An original normalized short Native span was not admitted as open.")
        }
        let result = try DefaultBRepRepairer().repair(input, request: request, tolerance: tolerance, using: &query)
        try require(result.model.edges[first.id] == nil && result.model.vertices[b.id] == nil
            && result.model.geometry.curves[curve1] == nil,
            "The first completely bounded original short edge was not collapsed.")
        try require(result.model.edges[second.id]?.startVertexID == a.id
            && result.model.edges[second.id]?.endVertexID == c.id
            && result.model.vertices[c.id]?.point == c.point && result.model.geometry.curves[curve2] == secondCurve,
            "A second short span hid its cumulative original displacement beyond the one allowance.")
        try require(result.after.isValid && result.diagnostics.isEmpty && input == saved
            && result.changes.filter { $0.action == .collapseSmallWireEdges && $0.scope == .loops }.count == 1
            && result.maximumDisplacement >= d && result.maximumDisplacement <= tolerance.distance,
            "A later audit lost the retained collapsed-curve source or original cumulative displacement.")
        // The later no-op shell action still audits the retained original collapsed image.
        // An abort after real candidate processing publishes neither that candidate nor a partial ledger.
        let budget = try OriginalQueryBudget(), trace = ValidationTrace(budget: budget, failAt: 2)
        var pending = try execution(budget)
        do {
            _ = try DefaultBRepRepairer(validator: Validator(trace: trace)).repair(input,
                request: request, tolerance: tolerance, using: &pending)
        } catch {
            guard let failure = original(error) as? Injected, case .sentinel = failure else { throw error }
            try require(input == saved && budget.snapshot.work > 0 && budget.snapshot.storageBytes > 0,
                "A terminal abort mutated the original model or refunded candidate/ledger admission.")
            return
        }
        throw Failure(message: "A terminal validator abort published the staged collapsed-curve ledger.")
    }
    static func sourceDepthIsIndependentFromAlgebraSelection() throws {
        var f = BRepRepairExecutionFixture.polylineSquare()
        f.model.geometry.curves[f.curveIDs[0]] = nil
        let input = f.model
        var admitted = try execution(OriginalQueryBudget(workLimit: 8_388_608), value: 0, coefficient: 0)
        _ = try repair(input, action: .reconstructCurveRepresentations, using: &admitted)
        var shallow = try execution(OriginalQueryBudget(workLimit: 8_388_608), source: 0)
        do {
            _ = try DefaultBRepRepairer().repair(input, request: .init(actions: [.reconstructCurveRepresentations]),
                tolerance: tolerance, using: &shallow)
        } catch {
            if let failure = original(error) as? GeometryConversionError, case .resourceLimitExceeded = failure {
                try require(input == f.model && shallow.effectiveLimits.remainingSourceDepth == 0,
                    "A source-depth refusal changed the retained input or increased the caller ceiling.")
                return
            }
            throw error
        }
        throw Failure(message: "A zero-source-depth caller reconstructed a new original lifted descendant.")
    }
}

import CADCore
import CADGeometry
import CADIR
import CADTopology
import CADKernel
import Synchronization

/// Actual public UV-splitter controls shared by Native and portable clients.
enum KernelUVSplitDiagnosticChecks {
    struct Failure: Error { let message: String }
    private static let tolerance = ModelingTolerance.standard

    private final class WorkCounter: Sendable {
        private let state = Mutex(0)
        func add(_ units: Int) { state.withLock { $0 += units } }
        var value: Int { state.withLock { $0 } }
    }

    private final class ProviderCalls: Sendable {
        struct State: Sendable {
            var direct = 0
            var ordinary = 0
            var ordinaryEntries = 0
            var ordinaryBudget: OriginalQueryBudget?
        }
        private let directBudget: OriginalQueryBudget
        private let state = Mutex(State())

        init(directBudget: OriginalQueryBudget) { self.directBudget = directBudget }
        var snapshot: State { state.withLock { $0 } }
        func ordinaryEntry() { state.withLock { $0.ordinaryEntries += 1 } }
        func observe(_ budget: OriginalQueryBudget) throws {
            try state.withLock { state in
                if budget === directBudget {
                    state.direct += 1
                } else {
                    if let owner = state.ordinaryBudget {
                        guard owner === budget else {
                            throw Failure(message: "A splitter request replaced its lower caller budget.")
                        }
                    } else {
                        state.ordinaryBudget = budget
                    }
                    state.ordinary += 1
                }
            }
        }
    }

    // Only the public provider protocol is conformed to; preparation capabilities
    // remain its opaque empty default, as for an external injected provider.
    private struct ExternalContainmentProvider: FacePointContainmentTesting {
        let calls: ProviderCalls
        func contains(_ point: Point3D, on faceID: FaceID, in model: BRepModel,
            tolerance: ModelingTolerance) throws -> Bool {
            calls.ordinaryEntry()
            return try DefaultFacePointContainmentTester().contains(point,
                on: faceID, in: model, tolerance: tolerance)
        }
        func contains(_ point: Point3D, on faceID: FaceID, in model: BRepModel,
            tolerance: ModelingTolerance, using execution: inout OriginalQueryExecution) throws -> Bool {
            try calls.observe(execution.budget)
            return try DefaultFacePointContainmentTester().contains(point,
                on: faceID, in: model, tolerance: tolerance, using: &execution)
        }
    }

    private static func require(_ value: Bool, _ message: String) throws {
        guard value else { throw Failure(message: message) }
    }

    private static func execution(work: Int = 8_388_608) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try .init(workLimit: work, storageByteLimit: 268_435_456),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .boundary, entry: .admitted, stage: .request))
    }

    private static func emptyGraph() -> BooleanIntersectionGraph {
        .init(facePairs: [], boundaryContacts: [], faceIntersections: [])
    }

    static func emptyGraphRemainsAGenuineEmptySplit() throws {
        var query = try execution()
        let graph = emptyGraph()
        let splitter: any BooleanUVFaceSplitting = DefaultBooleanUVFaceSplitter()
        let result = try splitter.splitGraph(intersectionGraph: graph, model: BRepModel(),
            tolerance: tolerance, using: &query)
        try require(result.splits.isEmpty && query.budget.snapshot.work > 1,
            "The actual empty graph bypassed validation or acquired a split.")
        let ordinary = try splitter.splitGraph(intersectionGraph: graph, model: BRepModel(), tolerance: tolerance)
        try require(ordinary == result, "Ordinary and direct empty splits disagree.")
    }

    static func lowerWorkRefusalRetainsItsOriginalClassification() throws {
        var query = try execution(work: 1)
        do {
            _ = try DefaultBooleanUVFaceSplitter().splitGraph(intersectionGraph: emptyGraph(),
                model: BRepModel(), tolerance: tolerance, using: &query)
            throw Failure(message: "Input graph validation escaped the one-work limit.")
        } catch {
            guard let failure = error as? OriginalQueryFailure,
                let scalar = failure.originalError as? ExactScalarFailure,
                case .resourceLimit(.work) = scalar else { throw error }
            try require(query.budget.snapshot.work == 1 && failure.kernelFailure.code == .resourceLimitExceeded
                && failure.context.operation == .boundary && failure.context.entry == .admitted
                && failure.context.stage == .refinement && failure.context.resource?.axis == .work,
                "UV graph validation changed its original work failure or caller context.")
            let needle = "input graph validation"
            let message = failure.kernelFailure.message
            let containsStage = message.utf8.indices.contains { message.utf8[$0...].starts(with: needle.utf8) }
            try require(containsStage, "UV graph validation lost its diagnostic stage.")
        }
    }

    static func lowerCallerCancellationRetainsItsOriginalCause() throws {
        let observed = WorkCounter()
        let budget = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456,
            consumeWorkUnits: { observed.add($0) }, checkpoint: {
                if observed.value >= 1 { throw CancellationError() }
            })
        var query = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .boundary, entry: .admitted, stage: .request))
        do {
            _ = try DefaultBooleanUVFaceSplitter().splitGraph(intersectionGraph: emptyGraph(),
                model: BRepModel(), tolerance: tolerance, using: &query)
            throw Failure(message: "The actual lower UV caller ignored cancellation.")
        } catch {
            guard error is CancellationError else { throw error }
            try require(budget.snapshot.work == 1 && observed.value == 1,
                "UV cancellation changed the admitted-work boundary.")
        }
    }

    private struct FaceFixture {
        let face: Face
        let loop: Loop
        let edges: [EdgeID: Edge]
        let curves: [CurveID: Curve3D]
        let vertices: [VertexID: Vertex]
        let edgeIDs: [EdgeID]
    }

    private static func contact(at point: Point3D) throws -> CurveSurfaceIntersection {
        try CurveSurfaceIntersection(point: point, curveParameter: 0.5, surfaceU: 0, surfaceV: -point.x,
            kind: .transverse, residual: 0, iterations: 0)
    }

    // Same authored projection/lift construction as CurvedBooleanUVSplitTests.makeFace.
    private static func makeFace(surfaceID: SurfaceID, surface: Surface3D,
        points: [Point3D]) throws -> FaceFixture {
        let vertexIDs = points.map { _ in VertexID() }
        let edgeIDs = points.map { _ in EdgeID() }
        let loopID = LoopID(), faceID = FaceID()
        let vertices = Dictionary(uniqueKeysWithValues: zip(vertexIDs, points).map {
            ($0.0, Vertex(id: $0.0, point: $0.1))
        })
        var curves: [CurveID: Curve3D] = [:]
        var pcurves: [SurfaceParameterCurve] = []
        let edges: [EdgeID: Edge] = try Dictionary(uniqueKeysWithValues: edgeIDs.indices.map { index in
            let edgeID = edgeIDs[index]
            let start = points[index], end = points[(index + 1) % points.count]
            let startParameter = try surface.parameterProjection(of: start, tolerance: tolerance)
            let endParameter = try surface.parameterProjection(of: end, tolerance: tolerance)
            let pcurve = SurfaceParameterCurve.polyline([
                SurfaceParameter(u: startParameter.u, v: startParameter.v),
                SurfaceParameter(u: endParameter.u, v: endParameter.v)])
            pcurves.append(pcurve)
            let curveID = CurveID()
            curves[curveID] = .surfaceLift(SurfaceLiftCurve3D(surface: surface, parameterCurve: pcurve))
            return (edgeID, Edge(id: edgeID, curveID: curveID, startVertexID: vertexIDs[index],
                endVertexID: vertexIDs[(index + 1) % vertexIDs.count]))
        })
        let loop = Loop(id: loopID, role: .outer, coedges: zip(edgeIDs, pcurves).map {
            Coedge(edgeID: $0.0, surfaceParameterCurve: $0.1)
        })
        return FaceFixture(face: Face(id: faceID, surfaceID: surfaceID, loops: [loopID]),
            loop: loop, edges: edges, curves: curves, vertices: vertices, edgeIDs: edgeIDs)
    }

    static func exactPlanarCutRetainsItsSourceAndUVLaw() throws {
        var query = try execution()
        try exactPlanarCut(provider: DefaultFacePointContainmentTester(), using: &query)
    }

    static func externalProviderRetainsItsEmptyCapabilityFallbackAndCaller() throws {
        var query = try execution()
        let monitor = ProviderCalls(directBudget: query.budget)
        try exactPlanarCut(provider: ExternalContainmentProvider(calls: monitor), using: &query)
        let calls = monitor.snapshot
        try require(calls.direct > 0 && calls.ordinary > 0 && calls.ordinaryEntries == 0,
            "UV splitting replaced its injected provider or bypassed its direct witness.")
        guard let ordinaryBudget = calls.ordinaryBudget else {
            throw Failure(message: "Ordinary splitting did not retain its independent caller owner.")
        }
        try require(ordinaryBudget !== query.budget && ordinaryBudget.snapshot.work > 0,
            "Ordinary splitting reused the admitted request's budget or skipped its lower provider.")
    }

    private static func exactPlanarCut(provider: any FacePointContainmentTesting,
        using query: inout OriginalQueryExecution) throws {
        print("UV_SPLIT_PLANAR_INPUT_PREPARATION_BEGIN")
        let target = Surface3D.analytic(.plane(origin: .origin, normal: .unitZ))
        let tool = Surface3D.analytic(.plane(origin: .origin, normal: .unitY))
        let targetID = SurfaceID(), toolID = SurfaceID()
        let targetFace = try makeFace(surfaceID: targetID, surface: target, points: [
            .init(x: -1, y: -1, z: 0), .init(x: 1, y: -1, z: 0),
            .init(x: 1, y: 1, z: 0), .init(x: -1, y: 1, z: 0)])
        let toolFace = try makeFace(surfaceID: toolID, surface: tool, points: [
            .init(x: -1, y: 0, z: -1), .init(x: -1, y: 0, z: 1),
            .init(x: 1, y: 0, z: 1), .init(x: 1, y: 0, z: -1)])
        let model = BRepModel(geometry: GeometryStore(
            curves: targetFace.curves.merging(toolFace.curves) { current, _ in current },
            surfaces: [targetID: target, toolID: tool]),
            faces: [targetFace.face.id: targetFace.face, toolFace.face.id: toolFace.face],
            loops: [targetFace.loop.id: targetFace.loop, toolFace.loop.id: toolFace.loop],
            edges: targetFace.edges.merging(toolFace.edges) { current, _ in current },
            vertices: targetFace.vertices.merging(toolFace.vertices) { current, _ in current })
        let pair = BooleanFacePairCandidate(targetFaceID: targetFace.face.id,
            toolFaceID: toolFace.face.id)
        let negativeX = Point3D(x: -1, y: 0, z: 0), positiveX = Point3D(x: 1, y: 0, z: 0)
        // The degree-one unit-weight source is exactly C(f)=(-1+2f,0,0).
        // Target basis (+Y,-X) and tool basis (-Z,-X) both lift (0,1-2f)
        // to that same source for every f in [0,1], with zero residual.
        let curve = Curve3D.bSpline(BSplineCurve3D(degree: 1, knots: [0, 0, 1, 1],
            controlPoints: [negativeX, positiveX], weights: [1, 1]))
        let law = SurfaceParameterCurve.affine(origin: .init(x: 0, y: 1),
            direction: .init(x: 0, y: -2), startParameter: 0, endParameter: 1)
        let anchor = try SurfaceParameterProjection(u: 0, v: 1, point: negativeX, residual: 0)
        let intersection = try SurfaceSurfaceIntersectionCurve(truth: .parametric(curve),
            derivedRepresentation: SurfaceSurfaceIntersectionDerivedRepresentation(curve: curve,
                firstSurfaceParameterCurve: law, secondSurfaceParameterCurve: law,
                maximumResidualUpperBound: 0, tolerance: tolerance), kind: .transverse,
            firstSurfaceAnchor: anchor, secondSurfaceAnchor: anchor, tolerance: tolerance)
        let graph = BooleanIntersectionGraph(facePairs: [pair], boundaryContacts: [
            .init(edgeID: targetFace.edgeIDs[1], curveFaceID: targetFace.face.id,
                surfaceFaceID: toolFace.face.id, geometry: .points([try contact(at: positiveX)])),
            .init(edgeID: targetFace.edgeIDs[3], curveFaceID: targetFace.face.id,
                surfaceFaceID: toolFace.face.id, geometry: .points([try contact(at: negativeX)]))],
            faceIntersections: [.init(facePair: pair, geometry: .curve(intersection))])
        try graph.validate(in: model, tolerance: tolerance)
        print("UV_SPLIT_PLANAR_INPUT_PREPARATION_END")
        let splitter: any BooleanUVFaceSplitting = DefaultBooleanUVFaceSplitter(
            facePointContainment: provider)
        let direct = try splitter.splitGraph(intersectionGraph: graph, model: model,
            tolerance: tolerance, using: &query)
        try checkPlanarCut(direct, pair: pair, start: positiveX, end: negativeX)
        try require(query.budget.snapshot.work > 1, "A nonempty split bypassed its actual caller work.")
        let ordinary = try splitter.splitGraph(intersectionGraph: graph, model: model, tolerance: tolerance)
        try checkPlanarCut(ordinary, pair: pair, start: positiveX, end: negativeX)
        print("UV_SPLIT_PLANAR work=\(query.budget.snapshot.work) bytes=\(query.budget.snapshot.storageBytes)")
    }

    private static func checkPlanarCut(_ graph: BooleanUVSplitGraph,
        pair: BooleanFacePairCandidate, start: Point3D, end: Point3D) throws {
        guard graph.splits.count == 1, let split = graph.splits.first,
            split.facePair == pair, split.components.count == 1,
            let component = split.components.first,
            case let .transverseSegment(actualStart, actualEnd) = component.geometry else {
            throw Failure(message: "The exact planar cut lost its single transverse segment.")
        }
        try require(actualStart.point == start && actualEnd.point == end
            && actualStart.targetU == 0 && actualStart.targetV == -1
            && actualStart.toolU == 0 && actualStart.toolV == -1
            && actualEnd.targetU == 0 && actualEnd.targetV == 1
            && actualEnd.toolU == 0 && actualEnd.toolV == 1
            && actualStart.residual == 0 && actualEnd.residual == 0,
            "The dyadic planar cut changed its exact points, UV law or zero residual.")
    }
}

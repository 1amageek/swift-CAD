import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections
import Synchronization

/// The real edge-length witness forwards to a real observed arc-length witness.
enum BRepRepairEdgeLengthChecks {
    typealias Checks = BRepRepairExecutionChecks
    private final class Trace: Sendable {
        private struct State: Sendable { var calls = 0; var limits: OriginalQueryExecutionLimits? }
        private let state = Mutex(State())
        let budget: OriginalQueryBudget?
        init(_ budget: OriginalQueryBudget? = nil) { self.budget = budget }
        var calls: Int { state.withLock { $0.calls } }
        var limits: OriginalQueryExecutionLimits? { state.withLock { $0.limits } }
        func record(_ limits: OriginalQueryExecutionLimits) {
            state.withLock { $0.calls += 1; $0.limits = limits }
        }
    }
    private struct Resolver: CurveArcLengthResolving {
        let trace: Trace
        func parameterization(of curve: Curve3D, over interval: ScalarInterval,
            options: CurveArcLengthOptions, tolerance: ModelingTolerance) throws -> any CurveArcLengthParameterization {
            throw Checks.Injected.ordinaryEntry
        }
        func parameterization(of curve: Curve3D, over interval: ScalarInterval, options: CurveArcLengthOptions,
            tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
            maximumAlgebraicDepth: Int?, using a: inout OriginalQueryExecution) throws -> any CurveArcLengthParameterization {
            throw Checks.Injected.sentinel
        }
        func enclosure(of curve: Curve3D, over interval: ScalarInterval, options: CurveArcLengthOptions,
            tolerance: ModelingTolerance) throws -> CurveArcLengthEnclosure { throw Checks.Injected.ordinaryEntry }
        func enclosure(of curve: Curve3D, over interval: ScalarInterval, options: CurveArcLengthOptions,
            tolerance: ModelingTolerance, maximumSubdivisionDepth: Int, remainingSourceDepth: Int,
            maximumAlgebraicDepth: Int?, using a: inout OriginalQueryExecution) throws -> CurveArcLengthEnclosure {
            try Checks.require((trace.budget == nil || trace.budget === a.budget) && options.absoluteAccuracy == nil
                && options.relativeAccuracy == 1e-10 && options.maximumSubdivisionDepth == 48
                && options.maximumIntervalCount == 131_072 && maximumSubdivisionDepth == 48
                && remainingSourceDepth == a.effectiveLimits.remainingSourceDepth && maximumAlgebraicDepth == nil,
                "The edge-length witness changed its owner, options, or independent optional policy.")
            trace.record(a.effectiveLimits)
            try a.consumeWork(5)
            return try DefaultCurveArcLengthResolver().enclosure(of: curve, over: interval,
                options: options, tolerance: tolerance, maximumSubdivisionDepth: maximumSubdivisionDepth,
                remainingSourceDepth: remainingSourceDepth, maximumAlgebraicDepth: maximumAlgebraicDepth, using: &a)
        }
        func parameterEnclosure(atArcLengthFraction fraction: Double, of curve: Curve3D, over interval: ScalarInterval,
            options: CurveArcLengthOptions, tolerance: ModelingTolerance) throws -> CurveArcLengthParameterEnclosure {
            throw Checks.Injected.ordinaryEntry
        }
        func parameterEnclosure(atArcLengthFraction fraction: Double, of curve: Curve3D, over interval: ScalarInterval,
            options: CurveArcLengthOptions, tolerance: ModelingTolerance,
            using a: inout OriginalQueryExecution) throws -> CurveArcLengthParameterEnclosure {
            throw Checks.Injected.sentinel
        }
    }
    static func line(trim: CurveTrim? = nil) -> (model: BRepModel, edge: Edge) {
        let sourceID = CurveID(), start = Vertex(point: .origin), end = Vertex(point: .init(x: 3, y: 0, z: 0))
        let edge = Edge(curveID: sourceID, startVertexID: start.id, endVertexID: end.id, trim: trim)
        let model = BRepModel(geometry: .init(curves: [sourceID: .line(.init(origin: .origin, direction: .unitX))]),
            edges: [edge.id: edge], vertices: [start.id: start, end.id: end])
        return (model, edge)
    }
    static func check(_ length: CurveArcLengthEnclosure, expected: Double) throws {
        try Checks.require(length.lowerBound <= expected && length.upperBound >= expected
            && length.upperBound - length.lowerBound <= ModelingTolerance.standard.distance * 2,
            "The certified edge length excludes its independent original metric value.")
    }
    static func intervalsAndRealInjectedResolver() throws {
        for trim in [nil, CurveTrim(startParameter: 3, endParameter: 0)] {
            let input = line(trim: trim), budget = try OriginalQueryBudget()
            let trace = Trace(budget)
            let port: any BRepEdgeLengthEvaluating = DefaultBRepEdgeLengthEvaluator(arcLengthResolver: Resolver(trace: trace))
            var a = try Checks.execution(budget)
            try a.consumeWork(11)
            try check(port.lengthEnclosure(of: input.edge, in: input.model, tolerance: .standard, using: &a), expected: 3)
            try Checks.require(trace.calls == 1 && budget.snapshot.work > 16,
                "The real arc-length witness was bypassed or reset the caller's prefix.")
        }
        let ordinaryInput = line(), ordinaryTrace = Trace()
        let ordinary = try DefaultBRepEdgeLengthEvaluator(arcLengthResolver: Resolver(trace: ordinaryTrace))
            .lengthEnclosure(of: ordinaryInput.edge, in: ordinaryInput.model, tolerance: .standard)
        try check(ordinary, expected: 3)
        try Checks.require(ordinaryTrace.calls == 1 && ordinaryTrace.limits?.maximumValueDepth == Int.max
            && ordinaryTrace.limits?.maximumCoefficientDepth == Int.max
            && ordinaryTrace.limits?.remainingSourceDepth == Int.max,
            "The ordinary length root leaked its classifier phase ceiling into the arc-length witness.")
        let sources: [(Curve3D, Double)] = [
            (.bSpline(.init(degree: 1, knots: [0, 0, 0.5, 1, 1],
                controlPoints: [.origin, .init(x: 1, y: 0, z: 0), .origin])), 2),
            (.circle(.init(center: .origin, normal: .unitZ, radius: 1)), Double.pi * 2)]
        for (curve, expected) in sources {
            let id = CurveID(), vertex = Vertex(point: try curve.point(at: 0, tolerance: .standard))
            let edge = Edge(curveID: id, startVertexID: vertex.id, endVertexID: vertex.id)
            let model = BRepModel(geometry: .init(curves: [id: curve]), edges: [edge.id: edge], vertices: [vertex.id: vertex])
            var a = try Checks.query()
            let port: any BRepEdgeLengthEvaluating = DefaultBRepEdgeLengthEvaluator()
            try check(port.lengthEnclosure(of: edge, in: model, tolerance: .standard, using: &a), expected: expected)
        }
        let pole = try Checks.poleSheet(), face = pole.model.faces.values.first!
        let host = pole.model.geometry.surfaces[face.surfaceID]!, id = CurveID()
        let curve = Curve3D.surfaceLift(.init(surface: host, parameterCurve: .constantV(v: 1, uStart: 0, uEnd: 1)))
        let edge = Edge(curveID: id, startVertexID: pole.pole, endVertexID: pole.pole,
            trim: .init(startParameter: 0, endParameter: 1))
        var model = pole.model; model.geometry.curves[id] = curve; model.edges[edge.id] = edge
        let budget = try OriginalQueryBudget(), trace = Trace(budget)
        var a = try Checks.execution(budget)
        let port: any BRepEdgeLengthEvaluating = DefaultBRepEdgeLengthEvaluator(arcLengthResolver: Resolver(trace: trace))
        let zero = try port.lengthEnclosure(of: edge, in: model, tolerance: .standard, using: &a)
        try Checks.require(zero.lowerBound == 0 && zero.upperBound == 0 && trace.calls == 0,
            "A singular parameter-incidence edge invoked regular arc length or lost exact zero.")
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
    static func resourcesCancellationAndMissingReferences() throws {
        let input = line(), source = input.model, observed = Checkpoints()
        func run(_ budget: OriginalQueryBudget) throws -> CurveArcLengthEnclosure {
            var a = try Checks.execution(budget)
            try a.consumeWork(11)
            let port: any BRepEdgeLengthEvaluating = DefaultBRepEdgeLengthEvaluator()
            return try port.lengthEnclosure(of: input.edge, in: source, tolerance: .standard, using: &a)
        }
        let measured = try OriginalQueryBudget(checkpoint: { try observed.check() })
        try check(run(measured), expected: 3)
        let n = measured.snapshot
        let exact = try OriginalQueryBudget(workLimit: n.work, storageByteLimit: n.storageBytes)
        try check(run(exact), expected: 3)
        try Checks.require(exact.snapshot.work == n.work && exact.snapshot.storageBytes == n.storageBytes,
            "The same edge input changed exact cumulative resource use.")
        for resource in [ExactResource.work, .storage] {
            let budget = try OriginalQueryBudget(workLimit: resource == .work ? n.work - 1 : nil,
                storageByteLimit: resource == .storage ? n.storageBytes - 1 : nil)
            do { _ = try run(budget) }
            catch {
                guard let failure = Checks.original(error) as? ExactScalarFailure,
                    case .resourceLimit(let actual) = failure, actual == resource else { throw error }
                continue
            }
            throw Checks.Failure(message: "An N-1 edge-length invocation published success.")
        }
        for stop in [1, observed.count / 2, observed.count] {
            let control = Checkpoints(stop: stop), budget = try OriginalQueryBudget(checkpoint: { try control.check() })
            do { _ = try run(budget) }
            catch {
                guard let failure = Checks.original(error) as? ExactScalarFailure, case .cancelled = failure else { throw error }
                try Checks.require(control.count == stop && source == input.model,
                    "Length cancellation changed source or the original observation point.")
                if stop == 1 { try Checks.require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0,
                    "Length entry cancellation spent query resources.") }
                continue
            }
            throw Checks.Failure(message: "A cancelled edge-length invocation published output.")
        }
        for missingCurve in [true, false] {
            var broken = source
            if missingCurve { broken.geometry.curves[input.edge.curveID] = nil }
            else { broken.vertices[input.edge.startVertexID] = nil }
            var a = try Checks.query()
            do { _ = try DefaultBRepEdgeLengthEvaluator().lengthEnclosure(of: input.edge, in: broken, tolerance: .standard, using: &a) }
            catch {
                guard let failure = Checks.original(error) as? TopologyError, case .missingReference = failure else { throw error }
                continue
            }
            throw Checks.Failure(message: "Missing edge source or endpoint became a length enclosure.")
        }
    }
}

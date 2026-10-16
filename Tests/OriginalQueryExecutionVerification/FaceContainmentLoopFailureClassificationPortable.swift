import CADCore
import CADGeometry
import CADTopology
import CADKernel
import HashTreeCollections
import Synchronization

/// Executes the three Native loop-failure oracles through the real Kernel session.
@main
struct FaceContainmentLoopFailureClassificationPortable {
    struct Failure: Error { let message: String }

    private struct Fixture {
        let model: BRepModel
        let surface: Surface3D
        let faceID: FaceID
        let loopID: LoopID
    }

    // Both escaping @Sendable callbacks retain this same synchronized owner.
    // The counter and checkpoint condition match the Native test's local Mutex.
    private final class ConsumedWork: Sendable {
        private let state = Mutex(0)
        func add(_ units: Int) { state.withLock { $0 += units } }
        var value: Int { state.withLock { $0 } }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }

    private static func containsDiagnostic(_ text: String, _ needle: String) -> Bool {
        if needle.isEmpty { return true }
        let haystack = text.utf8
        let pattern = needle.utf8
        for index in haystack.indices {
            if haystack[index...].starts(with: pattern) { return true }
        }
        return false
    }

    private static func execution(work: Int = 8_388_608) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: work,
            storageByteLimit: 268_435_456),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .boundary, entry: .prepared, stage: .source))
    }

    private static func fixture() throws -> Fixture {
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let surfaceID = SurfaceID(PortableIdentity128(high: 81, low: 1))
        let faceID = FaceID(PortableIdentity128(high: 82, low: 1))
        let loopID = LoopID(PortableIdentity128(high: 83, low: 1))
        let shellID = ShellID(PortableIdentity128(high: 84, low: 1))
        let bodyID = BodyID(PortableIdentity128(high: 85, low: 1))
        let pcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0, uStart: 0, uEnd: 1),
            .constantU(u: 1, vStart: 0, vEnd: 1),
            .constantV(v: 1, uStart: 1, uEnd: 0),
            .constantU(u: 0, vStart: 1, vEnd: 0),
        ]
        let edgeIDs = (1...4).map { EdgeID(PortableIdentity128(high: 86, low: UInt64($0))) }
        let curveIDs = (1...4).map { CurveID(PortableIdentity128(high: 87, low: UInt64($0))) }
        let vertexIDs = (1...4).map { VertexID(PortableIdentity128(high: 88, low: UInt64($0))) }
        // Public authored topology keeps every edge coupled to its original chart.
        // This is the same complete rectangle as the accepted Native fixture.
        var model = BRepModel(geometry: GeometryStore(surfaces: [surfaceID: surface]),
            bodies: [bodyID: Body(id: bodyID, sheetShellIDs: [shellID])],
            shells: [shellID: Shell(id: shellID, faceIDs: [faceID], orientation: .forward)],
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID], orientation: .forward)],
            loops: [loopID: Loop(id: loopID, role: .outer, coedges: edgeIDs.enumerated().map {
                Coedge(edgeID: $0.element, orientation: .forward, surfaceParameterCurve: pcurves[$0.offset])
            })])
        var authoring = try execution()
        for index in pcurves.indices {
            let start = try pcurves[index].parameter(atNormalizedFraction: 0,
                tolerance: .standard, using: &authoring)
            let point = try surface.point(u: start.u, v: start.v, tolerance: .standard, using: &authoring)
            model.vertices[vertexIDs[index]] = Vertex(id: vertexIDs[index], point: point)
            model.geometry.curves[curveIDs[index]] = .surfaceLift(SurfaceLiftCurve3D(
                surface: surface, parameterCurve: pcurves[index]))
            model.edges[edgeIDs[index]] = Edge(id: edgeIDs[index], curveID: curveIDs[index],
                startVertexID: vertexIDs[index], endVertexID: vertexIDs[(index + 1) % 4],
                trim: CurveTrim(startParameter: 0, endParameter: 1))
        }
        return Fixture(model: model, surface: surface, faceID: faceID, loopID: loopID)
    }

    static func authoredRectanglePreparesAndClassifiesItsOriginalUV() throws {
        let source = try fixture()
        var execution = try execution()
        let session = try DefaultFacePointContainmentTester().preparedContainmentSession(
            for: [source.faceID], in: source.model, tolerance: .standard, using: &execution)
        let inside = try session.containsParameter(.init(u: 0.5, v: 0.5),
            on: source.faceID, using: &execution)
        try require(inside == true, "The original rectangle did not contain its original UV center.")
        try require(execution.budget.snapshot.work > 4, "Prepared membership bypassed its caller work.")
    }

    static func lowerLoopWorkRefusalPreservesItsOriginalClassificationAndContext() throws {
        let source = try fixture()
        var validation = try execution()
        try source.surface.validate(tolerance: .standard, using: &validation)
        // Measure the actual source-validation prefix and four existing visits.
        let prefixWork = validation.budget.snapshot.work + 4
        try require(prefixWork > 0, "The lower-loop refusal had no completed prefix.")
        var execution = try execution(work: prefixWork)
        do {
            _ = try DefaultFacePointContainmentTester().preparedContainmentSession(
                for: [source.faceID], in: source.model, tolerance: .standard, using: &execution)
        } catch {
            guard let failure = error as? OriginalQueryFailure else { throw error }
            try require(execution.budget.snapshot.work == prefixWork, "The lower-loop work prefix changed.")
            try require(containsDiagnostic(failure.kernelFailure.message, "could not parameterize loop"),
                "The refusal did not cross the actual loop failure boundary.")
            try require(containsDiagnostic(failure.kernelFailure.message, source.loopID.description),
                "The refusal lost its loop diagnostic.")
            try require(containsDiagnostic(failure.kernelFailure.message, source.faceID.description),
                "The refusal lost its face diagnostic.")
            let lower = OriginalQueryFailure.published(failure.originalError,
                context: failure.context, tolerance: .standard)
            try require(OriginalQueryFailure.classification(of: lower)?.code == .resourceLimitExceeded,
                "The original lower cause lost its resource classification.")
            try require(failure.kernelFailure.code == .resourceLimitExceeded,
                "The Kernel boundary replaced the original resource classification.")
            try require(failure.context.operation == .boundary, "The caller operation changed.")
            try require(failure.context.entry == .prepared, "The caller entry changed.")
            try require(failure.context.stage == .source, "The caller stage changed.")
            try require(failure.context.resource?.axis == .work, "The original work resource axis changed.")
            return
        }
        throw Failure(message: "Loop preparation escaped its real caller work boundary.")
    }

    static func lowerLoopCallerCancellationKeepsItsCause() throws {
        let source = try fixture()
        var validation = try execution()
        try source.surface.validate(tolerance: .standard, using: &validation)
        let prefixWork = validation.budget.snapshot.work + 4
        let consumed = ConsumedWork()
        let budget = try OriginalQueryBudget(workLimit: 8_388_608,
            storageByteLimit: 268_435_456,
            consumeWorkUnits: { units in consumed.add(units) },
            checkpoint: {
                if consumed.value >= prefixWork { throw CancellationError() }
            })
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .boundary, entry: .prepared, stage: .source))
        do {
            _ = try DefaultFacePointContainmentTester().preparedContainmentSession(
                for: [source.faceID], in: source.model, tolerance: .standard, using: &execution)
        } catch {
            try require(budget.snapshot.work == prefixWork, "Cancellation changed the completed work prefix.")
            try require(consumed.value == prefixWork, "Cancellation changed the synchronized work observation.")
            try require(error is CancellationError, "The original cancellation cause was replaced.")
            return
        }
        throw Failure(message: "Loop preparation ignored its caller cancellation checkpoint.")
    }

    static func main() throws {
        try authoredRectanglePreparesAndClassifiesItsOriginalUV()
        print("PASS authoredRectanglePreparesAndClassifiesItsOriginalUV")
        try lowerLoopWorkRefusalPreservesItsOriginalClassificationAndContext()
        print("PASS lowerLoopWorkRefusalPreservesItsOriginalClassificationAndContext")
        try lowerLoopCallerCancellationKeepsItsCause()
        print("PASS lowerLoopCallerCancellationKeepsItsCause")
    }
}

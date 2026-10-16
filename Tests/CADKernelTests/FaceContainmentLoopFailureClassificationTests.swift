import CADCore
import CADGeometry
import CADTopology
import Testing
import Synchronization
@testable import CADKernel

@Suite("Face containment loop failure classification", .timeLimit(.minutes(1)))
struct FaceContainmentLoopFailureClassificationTests {
    private struct Fixture {
        let model: BRepModel
        let surface: Surface3D
        let faceID: FaceID
        let loopID: LoopID
    }

    private func execution(work: Int = 8_388_608) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: work,
            storageByteLimit: 268_435_456),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .boundary, entry: .prepared, stage: .source))
    }

    private func fixture() throws -> Fixture {
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
        // These are public authored topology values, with each edge coupled to
        // its exact original surface chart. No validation receipt is fabricated.
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

    @Test
    func authoredRectanglePreparesAndClassifiesItsOriginalUV() throws {
        let source = try fixture()
        var execution = try execution()
        let session = try DefaultFacePointContainmentTester().preparedContainmentSession(
            for: [source.faceID], in: source.model, tolerance: .standard, using: &execution)
        let inside = try session.containsParameter(.init(u: 0.5, v: 0.5),
            on: source.faceID, using: &execution)
        #expect(inside == true)
        #expect(execution.budget.snapshot.work > 4)
    }

    @Test
    func lowerLoopWorkRefusalPreservesItsOriginalClassificationAndContext() throws {
        let source = try fixture()
        var validation = try execution()
        try source.surface.validate(tolerance: .standard, using: &validation)
        // The real preparation visits session, face, region reserve and loop
        // before loopParameters enters SurfaceParameterTopology. Scope metadata
        // retains bytes, with the existing allocation policy contributing no work.
        let prefixWork = validation.budget.snapshot.work + 4
        #expect(prefixWork > 0)
        var execution = try execution(work: prefixWork)
        do {
            _ = try DefaultFacePointContainmentTester().preparedContainmentSession(
                for: [source.faceID], in: source.model, tolerance: .standard, using: &execution)
            Issue.record("Loop preparation escaped its real caller work boundary.")
        } catch {
            let failure = try #require(error as? OriginalQueryFailure)
            #expect(execution.budget.snapshot.work == prefixWork)
            #expect(failure.kernelFailure.message.contains("could not parameterize loop"))
            #expect(failure.kernelFailure.message.contains(source.loopID.description))
            #expect(failure.kernelFailure.message.contains(source.faceID.description))
            let lower = OriginalQueryFailure.published(failure.originalError,
                context: failure.context, tolerance: .standard)
            #expect(OriginalQueryFailure.classification(of: lower)?.code == .resourceLimitExceeded)
            #expect(failure.kernelFailure.code == .resourceLimitExceeded)
            #expect(failure.context.operation == .boundary)
            #expect(failure.context.entry == .prepared)
            #expect(failure.context.stage == .source)
            #expect(failure.context.resource?.axis == .work)
        }
    }
    @Test
    func lowerLoopCallerCancellationKeepsItsCause() throws {
        let source = try fixture()
        var validation = try execution()
        try source.surface.validate(tolerance: .standard, using: &validation)
        let prefixWork = validation.budget.snapshot.work + 4
        let consumed = Mutex(0)
        let budget = try OriginalQueryBudget(workLimit: 8_388_608,
            storageByteLimit: 268_435_456,
            consumeWorkUnits: { units in consumed.withLock { $0 += units } },
            checkpoint: {
                if consumed.withLock({ $0 >= prefixWork }) { throw CancellationError() }
            })
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .boundary, entry: .prepared, stage: .source))
        do {
            _ = try DefaultFacePointContainmentTester().preparedContainmentSession(
                for: [source.faceID], in: source.model, tolerance: .standard, using: &execution)
            Issue.record("Loop preparation ignored its caller cancellation checkpoint.")
        } catch {
            // The same completed nonzero prefix places this cancellation inside
            // loop parameterization, without substituting a resource failure.
            #expect(budget.snapshot.work == prefixWork)
            #expect(consumed.withLock { $0 } == prefixWork)
            #expect(error is CancellationError)
        }
    }

}

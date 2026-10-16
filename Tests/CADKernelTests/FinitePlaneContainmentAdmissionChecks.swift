import CADCore
import CADGeometry
import CADTopology
import CADKernel
import HashTreeCollections
import Synchronization

/// Real prepared finite-plane proximity controls; no intersection authority is issued.
enum FinitePlaneContainmentAdmissionChecks {
    struct Failure: Error { let message: String }
    private static let tolerance = ModelingTolerance.standard

    private final class WorkCounter: Sendable {
        private let state = Mutex(0)
        func add(_ units: Int) { state.withLock { $0 += units } }
        var value: Int { state.withLock { $0 } }
    }

    private struct Fixture {
        var model: BRepModel
        let surface: Surface3D
        let faceID: FaceID
    }

    private struct Prepared {
        let session: any FacePointContainmentSession
        let faceID: FaceID
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }

    private static func execution(work: Int = 8_388_608,
        counter: WorkCounter? = nil, cancelAt: Int? = nil) throws -> OriginalQueryExecution {
        let budget = try OriginalQueryBudget(workLimit: work, storageByteLimit: 268_435_456,
            consumeWorkUnits: { counter?.add($0) }, checkpoint: {
                if let cancelAt, let counter, counter.value >= cancelAt {
                    throw CancellationError()
                }
            })
        return OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .boundary, entry: .prepared, stage: .source))
    }

    private static func fixture(analytic: Bool) throws -> Fixture {
        let surface: Surface3D = analytic
            ? .analytic(.plane(origin: .origin, normal: .unitZ))
            : .plane(Plane3D(origin: .origin, normal: .unitZ))
        let surfaceID = SurfaceID(), faceID = FaceID(), loopID = LoopID()
        let pcurves: [SurfaceParameterCurve] = [
            .constantV(v: 0, uStart: 0, uEnd: 1),
            .constantU(u: 1, vStart: 0, vEnd: 1),
            .constantV(v: 1, uStart: 1, uEnd: 0),
            .constantU(u: 0, vStart: 1, vEnd: 0)]
        let edgeIDs = pcurves.map { _ in EdgeID() }
        let curveIDs = pcurves.map { _ in CurveID() }
        let vertexIDs = pcurves.map { _ in VertexID() }
        var model = BRepModel(geometry: GeometryStore(surfaces: [surfaceID: surface]),
            faces: [faceID: Face(id: faceID, surfaceID: surfaceID, loops: [loopID])],
            loops: [loopID: Loop(id: loopID, role: .outer, coedges: pcurves.indices.map {
                Coedge(edgeID: edgeIDs[$0], surfaceParameterCurve: pcurves[$0])
            })])
        var authoring = try execution()
        for index in pcurves.indices {
            let start = try pcurves[index].parameter(atNormalizedFraction: 0,
                tolerance: tolerance, using: &authoring)
            model.vertices[vertexIDs[index]] = Vertex(id: vertexIDs[index],
                point: try surface.point(u: start.u, v: start.v,
                    tolerance: tolerance, using: &authoring))
            model.geometry.curves[curveIDs[index]] = .surfaceLift(.init(
                surface: surface, parameterCurve: pcurves[index]))
            model.edges[edgeIDs[index]] = Edge(id: edgeIDs[index], curveID: curveIDs[index],
                startVertexID: vertexIDs[index], endVertexID: vertexIDs[(index + 1) % 4],
                trim: CurveTrim(startParameter: 0, endParameter: 1))
        }
        return Fixture(model: model, surface: surface, faceID: faceID)
    }

    private static func prepared(analytic: Bool) throws -> Prepared {
        var source = try fixture(analytic: analytic)
        var authoring = try execution()
        let provider: any FacePointContainmentTesting = DefaultFacePointContainmentTester()
        let session = try provider.preparedContainmentSession(for: [source.faceID],
            in: source.model, tolerance: tolerance, using: &authoring)
        // The session must retain the original source after authored COW removal
        // and after this function releases the model and preparation execution.
        source.model.geometry.surfaces.removeAll(where: { _ in true })
        source.model.geometry.curves.removeAll(where: { _ in true })
        source.model.faces.removeAll(where: { _ in true })
        source.model.loops.removeAll(where: { _ in true })
        try require(source.model.faces.isEmpty && source.model.geometry.surfaces.isEmpty,
            "The authored COW lifetime control did not remove its source.")
        return Prepared(session: session, faceID: source.faceID)
    }

    static func finitePlaneProximityUsesRetainedMaterialAndSource() throws {
        for analytic in [false, true] {
            let source = try fixture(analytic: analytic)
            let point = Point3D(x: -0.5, y: 0.5, z: tolerance.distance * 0.5)
            let provider: any FacePointContainmentTesting = DefaultFacePointContainmentTester()
            var query = try execution()
            let direct = try provider.contains(point, on: source.faceID, in: source.model,
                tolerance: tolerance, using: &query)
            let ordinary = try provider.contains(point, on: source.faceID, in: source.model,
                tolerance: tolerance)
            try require(direct && ordinary && query.budget.snapshot.work > 0,
                "A point within the original plane's proximity threshold lost finite material membership.")
            let retained = try prepared(analytic: analytic)
            var read = try execution()
            let retainedDirect = try retained.session.contains(point, on: retained.faceID, using: &read)
            let retainedOrdinary = try retained.session.contains(point, on: retained.faceID)
            try require(retainedDirect && retainedOrdinary && point.z != 0,
                "Retained finite-plane proximity changed after its authored source was released.")
        }
    }

    static func finiteBoundsAndOutsideToleranceKeepTheirCompletePath() throws {
        for analytic in [false, true] {
            let source = try fixture(analytic: analytic)
            let retained = try prepared(analytic: analytic)
            let outsideUV = Point3D(x: -2, y: 0.5, z: 0)
            var projection = try execution()
            let candidate = try source.surface.parameterProjectionResult(of: outsideUV,
                tolerance: tolerance, using: &projection)
            guard case .projected(let value) = candidate else {
                throw Failure(message: "The outside-box control lost its genuine plane candidate.")
            }
            try require(value.u == 0.5 && value.v == 2 && value.residual == 0,
                "The plane control no longer projects outside the finite original UV rectangle.")
            var outsideRead = try execution()
            let outside = try retained.session.contains(outsideUV, on: retained.faceID, using: &outsideRead)
            var separatedRead = try execution()
            let separated = try retained.session.contains(
                .init(x: -0.5, y: 0.5, z: tolerance.distance * 2),
                on: retained.faceID, using: &separatedRead)
            try require(!outside && !separated,
                "A native plane candidate escaped finite trim or complete distance exclusion.")
        }
    }

    static func primitiveProjectionPreservesCallerWorkAndCancellation() throws {
        let retained = try prepared(analytic: false)
        let point = Point3D(x: -0.5, y: 0.5, z: tolerance.distance * 0.5)
        // A fresh reader admits the retained owner with zero work. Session and
        // containment each charge one visit before Geometry validates the plane.
        var limited = try execution(work: 2)
        do {
            _ = try retained.session.contains(point, on: retained.faceID, using: &limited)
            throw Failure(message: "Primitive projection escaped the real lower work boundary.")
        } catch {
            guard let failure = error as? OriginalQueryFailure,
                let scalar = failure.originalError as? ExactScalarFailure,
                case .resourceLimit(.work) = scalar else { throw error }
            try require(limited.budget.snapshot.work == 2
                && failure.kernelFailure.code == .resourceLimitExceeded
                && failure.context.resource?.axis == .work
                && failure.context.stage == .membership,
                "Primitive projection replaced its original resource cause or caller context.")
        }
        let counter = WorkCounter()
        var cancelled = try execution(counter: counter, cancelAt: 3)
        do {
            _ = try retained.session.contains(point, on: retained.faceID, using: &cancelled)
            throw Failure(message: "Primitive projection ignored its caller cancellation.")
        } catch {
            guard error is CancellationError else { throw error }
            try require(counter.value == 3 && cancelled.budget.snapshot.work == 3,
                "Cancellation moved before the real Geometry source-validation work.")
        }
        var positive = try execution()
        let result = try retained.session.contains(point, on: retained.faceID, using: &positive)
        try require(result, "A refused reader damaged the retained original source session.")
    }
}

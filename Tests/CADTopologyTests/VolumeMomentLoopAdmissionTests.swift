import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections
import Synchronization

#if !VOLUME_MOMENT_PORTABLE
import Testing

@Suite("Volume moment loop admission", .timeLimit(.minutes(1)))
struct VolumeMomentLoopAdmissionTests {
    @Test func retainedCubeReceiptAdmitsAllTenIndependentMoments() throws {
        try VolumeMomentLoopAdmissionChecks.retainedCubeReceiptAdmitsAllTenIndependentMoments()
    }
    @Test func queryUsesExactCumulativeWorkAndStorageBoundaries() throws {
        try VolumeMomentLoopAdmissionChecks.queryUsesExactCumulativeWorkAndStorageBoundaries()
    }
    @Test func queryPreservesIndependentIncomingAlgebraAxes() throws {
        try VolumeMomentLoopAdmissionChecks.queryPreservesIndependentIncomingAlgebraAxes()
    }
    @Test func queryRefusesEntryInProgressAndLastCheckpointCancellation() throws {
        try VolumeMomentLoopAdmissionChecks.queryRefusesEntryInProgressAndLastCheckpointCancellation()
    }
    @Test func receiptSurvivesAuthoredSourceMutationAndResultOutlivesQuery() throws {
        try VolumeMomentLoopAdmissionChecks.receiptSurvivesAuthoredSourceMutationAndResultOutlivesQuery()
    }
}
#endif

enum VolumeMomentLoopAdmissionChecks {
    struct Failure: Error { let message: String }
    static let tolerance = ModelingTolerance.standard
    static let options = BRepVolumeMomentOptions(absoluteAccuracy: 1e-5)

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }

    static func execution(_ budget: OriginalQueryBudget, valueDepth: Int = 32,
        coefficientDepth: Int = 32) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget, limits: try .init(maximumValueDepth: valueDepth,
            maximumCoefficientDepth: coefficientDepth, remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
    }

    // Reuses the independently authored unit-cube geometry of the original Mass fixture.
    static func cube() -> (model: BRepModel, bodyID: BodyID) {
        let points = [Point3D(x: 0, y: 0, z: 0), .init(x: 1, y: 0, z: 0),
            .init(x: 1, y: 1, z: 0), .init(x: 0, y: 1, z: 0),
            .init(x: 0, y: 0, z: 1), .init(x: 1, y: 0, z: 1),
            .init(x: 1, y: 1, z: 1), .init(x: 0, y: 1, z: 1)]
        let vertices = points.enumerated().map {
            Vertex(id: VertexID(PortableIdentity128(high: 1, low: UInt64($0.offset + 1))), point: $0.element)
        }
        var model = BRepModel()
        for vertex in vertices { model.vertices[vertex.id] = vertex }
        var edges: [String: Edge] = [:]
        var faceIDs: [FaceID] = []
        for indexes in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4],
                        [3, 7, 6, 2], [0, 4, 7, 3], [1, 2, 6, 5]] {
            let faceOrdinal = UInt64(faceIDs.count + 1)
            let origin = points[indexes[0]]
            let u = points[indexes[1]] - origin
            let v = points[indexes[3]] - origin
            let surfaceID = SurfaceID(PortableIdentity128(high: 2, low: faceOrdinal))
            model.geometry.surfaces[surfaceID] = .plane(.init(origin: origin,
                normal: u.cross(v), uDirection: u))
            let parameters = [SurfaceParameter(u: 0, v: 0), .init(u: 1, v: 0),
                .init(u: 1, v: 1), .init(u: 0, v: 1)]
            var coedges: [Coedge] = []
            for index in indexes.indices {
                let first = indexes[index], second = indexes[(index + 1) % 4]
                let low = min(first, second), high = max(first, second)
                let key = "\(low):\(high)"
                let edge: Edge
                if let existing = edges[key] { edge = existing }
                else {
                    let ordinal = UInt64(edges.count + 1)
                    let curveID = CurveID(PortableIdentity128(high: 3, low: ordinal))
                    model.geometry.curves[curveID] = .line(.init(origin: points[low],
                        direction: points[high] - points[low]))
                    edge = Edge(id: EdgeID(PortableIdentity128(high: 4, low: ordinal)),
                        curveID: curveID, startVertexID: vertices[low].id,
                        endVertexID: vertices[high].id, trim: .init(startParameter: 0, endParameter: 1))
                    edges[key] = edge
                    model.edges[edge.id] = edge
                }
                coedges.append(Coedge(edgeID: edge.id, orientation: first == low ? .forward : .reversed,
                    surfaceParameterCurve: .polyline([parameters[index], parameters[(index + 1) % 4]])))
            }
            let loop = Loop(id: LoopID(PortableIdentity128(high: 5, low: faceOrdinal)),
                role: .outer, coedges: coedges)
            model.loops[loop.id] = loop
            let face = Face(id: FaceID(PortableIdentity128(high: 6, low: faceOrdinal)),
                surfaceID: surfaceID, loops: [loop.id])
            model.faces[face.id] = face
            faceIDs.append(face.id)
        }
        let shell = Shell(id: ShellID(PortableIdentity128(high: 7, low: 1)), faceIDs: faceIDs)
        model.shells[shell.id] = shell
        let body = Body(id: BodyID(PortableIdentity128(high: 8, low: 1)),
            solidComponents: [.init(outerShellID: shell.id)])
        model.bodies[body.id] = body
        return (model, body.id)
    }

    static func retainedCubeReceiptAdmitsAllTenIndependentMoments() throws {
        let input = cube()
        try require(input.model.vertices.count == 8 && input.model.edges.count == 12
            && input.model.faces.count == 6 && input.model.loops.values.allSatisfy { $0.coedges.count == 4 },
            "The authored six-face cube topology changed.")
        let preparationBudget = try OriginalQueryBudget()
        var preparation = try execution(preparationBudget)
        print("MOMENT_RECEIPT_PREPARATION_BEGIN")
        // The public convenience policy selects local algebra32, as ordinary validation does.
        let receipt = try ValidatedBRepModel(input.model, tolerance: tolerance, using: &preparation)
        print("MOMENT_RECEIPT_PREPARATION_END work=\(preparationBudget.snapshot.work) bytes=\(preparationBudget.snapshot.storageBytes)")
        try require(receipt.validationLevel == .exact && preparationBudget.snapshot.work > 0,
            "The cube did not obtain an authentic exact public receipt.")
        let preparationWork = preparationBudget.snapshot.work
        let budget = try OriginalQueryBudget(workLimit: options.maximumWork)
        var admission = try execution(budget)
        let provider: any BRepVolumeMomentMeasuring = DefaultBRepVolumeMomentMeasurer()
        print("MOMENT_RECEIPT_QUERY_BEGIN")
        let result = try provider.moments(of: input.bodyID, in: receipt,
            options: options, using: &admission)
        print("MOMENT_RECEIPT_QUERY_END work=\(budget.snapshot.work) bytes=\(budget.snapshot.storageBytes)")
        try require(preparationBudget.snapshot.work == preparationWork,
            "Moment integration changed its separate completed receipt operation.")
        try checkMoments(result)
        try require(result.consumedWork > 0 && result.consumedWork <= options.maximumWork,
            "Moment consumption escaped its unchanged request ceiling.")
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

    static func preparedCube() throws -> (receipt: ValidatedBRepModel, bodyID: BodyID) {
        let input = cube()
        let budget = try OriginalQueryBudget()
        var preparation = try execution(budget)
        print("MOMENT_RECEIPT_PREPARATION_BEGIN")
        let receipt = try ValidatedBRepModel(input.model, tolerance: tolerance, using: &preparation)
        print("MOMENT_RECEIPT_PREPARATION_END work=\(budget.snapshot.work) bytes=\(budget.snapshot.storageBytes)")
        return (receipt, input.bodyID)
    }

    static func query(_ input: (receipt: ValidatedBRepModel, bodyID: BodyID),
        using admission: inout OriginalQueryExecution) throws -> BRepVolumeMoments {
        let provider: any BRepVolumeMomentMeasuring = DefaultBRepVolumeMomentMeasurer()
        return try provider.moments(of: input.bodyID, in: input.receipt, options: options, using: &admission)
    }

    static func checkMoments(_ result: BRepVolumeMoments) throws {
        let thirdLower = 0x1.5555555555555p-2
        let thirdUpper = 0x1.5555555555556p-2
        let expected = [1.0, 0.5, 0.5, 0.5, thirdLower, thirdLower, thirdLower, 0.25, 0.25, 0.25]
        try require(result.enclosures.count == 10, "Moment publication lost an integral.")
        for index in expected.indices {
            let box = result.enclosures[index]
            // Finite binary64 endpoints enclose exact 1/3 iff they cover both adjacent dyadics.
            let upper = (4...6).contains(index) ? thirdUpper : expected[index]
            try require(box.lower <= expected[index] && upper <= box.upper,
                "A cube moment excluded its independent analytic value.")
            try require((box.upper - box.lower).nextUp <= options.absoluteAccuracy,
                "A cube moment exceeded its requested width.")
        }
    }

    static func original(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return original(failure.originalError) }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let cause) = scalar {
            return original(cause)
        }
        return error
    }

    static func queryUsesExactCumulativeWorkAndStorageBoundaries() throws {
        let input = try preparedCube()
        func run(_ budget: OriginalQueryBudget) throws -> BRepVolumeMoments {
            var admission = try execution(budget)
            try admission.consumeWork(13)
            let result = try query(input, using: &admission)
            try require(result.consumedWork == admission.localWork - 13
                && budget.snapshot.work == admission.localWork, "Moment work lost its original caller attribution.")
            try checkMoments(result)
            return result
        }
        let measured = try OriginalQueryBudget()
        let expected = try run(measured)
        let n = measured.snapshot
        let exact = try OriginalQueryBudget(workLimit: n.work, storageByteLimit: n.storageBytes)
        let repeated = try run(exact)
        try require(repeated.enclosures == expected.enclosures && exact.snapshot.work == n.work
            && exact.snapshot.storageBytes == n.storageBytes, "The same receipt's exact resource trace changed.")
        for resource in [ExactResource.work, .storage] {
            let short = try OriginalQueryBudget(workLimit: resource == .work ? n.work - 1 : nil,
                storageByteLimit: resource == .storage ? n.storageBytes - 1 : nil)
            do { _ = try run(short); throw Failure(message: "An N-1 moment query published output.") }
            catch {
                guard let scalar = original(error) as? ExactScalarFailure,
                    case .resourceLimit(let actual) = scalar, actual == resource else { throw error }
            }
            try require(short.snapshot.work <= (resource == .work ? n.work - 1 : n.work)
                && short.snapshot.storageBytes <= (resource == .storage ? n.storageBytes - 1 : n.storageBytes),
                "A refused resource request was committed.")
        }
        print("MOMENT_EXACT_BOUNDARY work=\(n.work) bytes=\(n.storageBytes)")
    }

    static func queryPreservesIndependentIncomingAlgebraAxes() throws {
        let input = try preparedCube()
        for (valueDepth, coefficientDepth) in [(0, 32), (32, 0), (0, 0)] {
            var admission = try execution(OriginalQueryBudget(workLimit: options.maximumWork),
                valueDepth: valueDepth, coefficientDepth: coefficientDepth)
            try checkMoments(query(input, using: &admission))
            try require(admission.effectiveLimits.maximumValueDepth == valueDepth
                && admission.effectiveLimits.maximumCoefficientDepth == coefficientDepth
                && admission.valueDepth <= valueDepth && admission.coefficientDepth <= coefficientDepth,
                "The local algebra selection widened an independent incoming axis.")
            print("MOMENT_ALGEBRA_AXES value=\(admission.valueDepth)/\(valueDepth) coefficient=\(admission.coefficientDepth)/\(coefficientDepth)")
        }
    }

    static func queryRefusesEntryInProgressAndLastCheckpointCancellation() throws {
        let input = try preparedCube()
        let observed = Checkpoints()
        let budget = try OriginalQueryBudget(workLimit: options.maximumWork, checkpoint: { try observed.check() })
        var admission = try execution(budget)
        try checkMoments(query(input, using: &admission))
        try require(observed.count > 2, "The query exposed no in-progress cancellation point.")
        for stop in [1, observed.count / 2, observed.count] {
            let control = Checkpoints(stop: stop)
            let cancelled = try OriginalQueryBudget(workLimit: options.maximumWork, checkpoint: { try control.check() })
            var pending = try execution(cancelled)
            do { _ = try query(input, using: &pending); throw Failure(message: "A cancelled moment query published output.") }
            catch {
                guard let scalar = original(error) as? ExactScalarFailure,
                    case .cancelled = scalar else { throw error }
            }
            try require(control.count == stop, "Cancellation occurred at a different caller checkpoint.")
            if stop == 1 {
                try require(cancelled.snapshot.work == 0 && cancelled.snapshot.storageBytes == 0,
                    "Entry cancellation consumed query resources.")
            } else { try require(cancelled.snapshot.work > 0, "In-progress cancellation reset admitted work.") }
            print("MOMENT_CANCEL checkpoint=\(stop)/\(observed.count)")
        }
    }

    static func receiptSurvivesAuthoredSourceMutationAndResultOutlivesQuery() throws {
        func retained() throws -> BRepVolumeMoments {
            var input = cube()
            let preparationBudget = try OriginalQueryBudget()
            var preparation = try execution(preparationBudget)
            let receipt = try ValidatedBRepModel(input.model, tolerance: tolerance, using: &preparation)
            print("MOMENT_COW_PREPARATION work=\(preparationBudget.snapshot.work) bytes=\(preparationBudget.snapshot.storageBytes)")
            let vertexID = VertexID(PortableIdentity128(high: 1, low: 1))
            input.model.vertices[vertexID] = Vertex(id: vertexID, point: .init(x: 99, y: 0, z: 0))
            input.model.geometry.surfaces.removeAll(where: { _ in true })
            input.model.loops.removeAll(where: { _ in true })
            try require(receipt.model.vertices[vertexID]?.point == .origin
                && receipt.model.geometry.surfaces.count == 6 && receipt.model.loops.count == 6,
                "Authored source mutation changed the immutable validated receipt.")
            var admission = try execution(OriginalQueryBudget(workLimit: options.maximumWork))
            return try query((receipt, input.bodyID), using: &admission)
        }
        // Receipt, source authoring buffers and caller execution are out of scope here.
        let result = try retained()
        try checkMoments(result)
    }
}

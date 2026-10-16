import CADCore
import CADGeometry
import CADTopology
import HashTreeCollections
import Synchronization

/// Public volume admission over the original authored unit cube.
enum VolumeCallerAdmissionChecks {
    private typealias Shared = VolumeMomentLoopAdmissionChecks
    private typealias Input = (model: BRepModel, bodyID: BodyID)
    struct Failure: Error { let message: String }
    static let tolerance = Shared.tolerance

    private enum Query: String, CaseIterable {
        case all, body, shell, volumetric
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

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }

    private static func shellID(_ input: Input) throws -> ShellID {
        guard let id = input.model.bodies[input.bodyID]?.shellIDs.first else {
            throw Failure(message: "The authored unit cube lost its shell.")
        }
        return id
    }

    private static func evaluate(_ query: Query, _ input: Input,
        using execution: inout OriginalQueryExecution) throws -> Double? {
        switch query {
        case .all:
            return try input.model.volume(tolerance: tolerance, using: &execution)
        case .body:
            return try input.model.volume(of: input.bodyID, tolerance: tolerance, using: &execution)
        case .shell:
            return try input.model.signedVolume(ofShell: shellID(input), tolerance: tolerance, using: &execution)
        case .volumetric:
            try input.model.validate(level: .volumetric, tolerance: tolerance, using: &execution)
            return nil
        }
    }

    private static func check(_ value: Double?, query: Query) throws {
        if query == .volumetric {
            try require(value == nil, "Validation unexpectedly published a measurement.")
        } else {
            guard let value else { throw Failure(message: "A volume query lost its result.") }
            try require(abs(value - 1) <= tolerance.distance,
                "The authored unit cube lost its independent volume one.")
        }
    }

    static func publicVolumesRetainTheirValuesAndMandatoryLowerCost() throws {
        let input = Shared.cube()
        let shellID = try shellID(input)
        guard let shell = input.model.shells[shellID], shell.faceIDs.count == 6 else {
            throw Failure(message: "The authored unit cube lost its six-face shell.")
        }
        try require(abs(try input.model.volume(tolerance: tolerance) - 1) <= tolerance.distance,
            "Ordinary whole-model volume changed.")
        try require(abs(try input.model.volume(of: input.bodyID, tolerance: tolerance) - 1) <= tolerance.distance,
            "Ordinary body volume changed.")
        try require(abs(try input.model.signedVolume(ofShell: shellID, tolerance: tolerance) - 1) <= tolerance.distance,
            "Ordinary signed shell volume changed.")
        try input.model.validate(level: .volumetric, tolerance: tolerance)

        // P is the identical public base validation selected first by signedVolume.
        let baseBudget = try OriginalQueryBudget()
        var base = try Shared.execution(baseBudget)
        try input.model.validate(tolerance: tolerance, using: &base)
        let p = baseBudget.snapshot.work

        // L is the SECOND reference/plane traversal, after base validation returned.
        // These are actual original producers, not replacements or measured approximations.
        let lowerBudget = try OriginalQueryBudget()
        var lower = try Shared.execution(lowerBudget)
        let reference = try BRepShellReferencePointResolver().referencePoint(for: shell, in: input.model,
            context: "Line-only shell volume", using: &lower)
        try require(reference == Point3D(x: 0.5, y: 0.5, z: 0.5), "The original shell reference changed.")
        for faceID in shell.faceIDs {
            guard let face = input.model.faces[faceID], let source = input.model.geometry.surfaces[face.surfaceID],
                let _ = try DefaultPlanarSurfaceResolver().exactPlane(for: source,
                    tolerance: tolerance, using: &lower) else {
                throw Failure(message: "The authored face lost its exact source plane.")
            }
        }
        let l = lowerBudget.snapshot.work

        // O uses the same public ordered-point body as volume's private invocation.
        // Its entry only constructs the immutable invocation, with no paid prefix.
        let pointsBudget = try OriginalQueryBudget()
        var points = try Shared.execution(pointsBudget)
        for faceID in shell.faceIDs {
            guard let face = input.model.faces[faceID] else { throw Failure(message: "Missing cube face.") }
            for loopID in face.loops {
                let ordered = try input.model.orderedPoints(for: loopID, using: &points)
                try require(ordered.count == 4, "A cube face lost its four original corners.")
            }
        }
        let o = pointsBudget.snapshot.work
        // Six faces + six loops + 24 line-edge visits + 12 triangles = 48.
        // This is the fixed incidence trace, separate from lower numeric/source work.
        let expected = p + l + o + 48
        try require(p > 0 && l > 0 && o > 0, "The real composition had no admitted lower work.")
        for query in Query.allCases {
            let budget = try OriginalQueryBudget()
            var execution = try Shared.execution(budget)
            try execution.consumeWork(13)
            try check(evaluate(query, input, using: &execution), query: query)
            try require(execution.localWork == budget.snapshot.work && execution.localWork > 13,
                "A public volume operation reset its original caller attribution.")
            if query == .shell {
                try require(budget.snapshot.work - 13 == expected,
                    "Signed volume did not pay base validation plus its actual second lower traversal and incidence work.")
                print("VOLUME_LOWER_COMPOSITION base=\(p) secondLower=\(l) orderedPoints=\(o) incidence=48 public=\(budget.snapshot.work - 13)")
            }
        }
    }

    static func exactCumulativeWorkAndStorageRefuseShortBudgets() throws {
        let input = Shared.cube()
        for query in [Query.body, .volumetric] {
            func run(_ budget: OriginalQueryBudget) throws {
                var execution = try Shared.execution(budget)
                try execution.consumeWork(13)
                try check(evaluate(query, input, using: &execution), query: query)
                try require(execution.localWork == budget.snapshot.work,
                    "The request lost its prior caller work.")
            }
            let measured = try OriginalQueryBudget()
            try run(measured)
            let n = measured.snapshot
            try require(n.work > 13 && n.storageBytes > 0, "The public query reported no actual resources.")
            let exact = try OriginalQueryBudget(workLimit: n.work, storageByteLimit: n.storageBytes)
            try run(exact)
            try require(exact.snapshot.work == n.work && exact.snapshot.storageBytes == n.storageBytes,
                "The same retained cube's exact trace changed.")
            for resource in [ExactResource.work, .storage] {
                let short = try OriginalQueryBudget(workLimit: resource == .work ? n.work - 1 : nil,
                    storageByteLimit: resource == .storage ? n.storageBytes - 1 : nil)
                do { try run(short); throw Failure(message: "An N-1 public query published success.") }
                catch {
                    guard let scalar = Shared.original(error) as? ExactScalarFailure,
                        case .resourceLimit(let actual) = scalar, actual == resource else { throw error }
                }
                try require(short.snapshot.work <= (resource == .work ? n.work - 1 : n.work)
                    && short.snapshot.storageBytes <= (resource == .storage ? n.storageBytes - 1 : n.storageBytes),
                    "A rejected resource debit was committed.")
            }
            let zero = try OriginalQueryBudget(storageByteLimit: 0)
            do { try run(zero); throw Failure(message: "Zero storage published a public volume result.") }
            catch {
                guard let scalar = Shared.original(error) as? ExactScalarFailure,
                    case .resourceLimit(.storage) = scalar else { throw error }
            }
            try require(zero.snapshot.storageBytes == 0, "Zero storage admitted an allocation.")
            print("VOLUME_EXACT_BOUNDARY query=\(query.rawValue) work=\(n.work) bytes=\(n.storageBytes)")
        }
    }

    static func entryInProgressAndLastCheckpointCancellationPropagate() throws {
        let input = Shared.cube()
        for query in Query.allCases {
            let observed = Checkpoints()
            let baseline = try OriginalQueryBudget(checkpoint: { try observed.check() })
            var execution = try Shared.execution(baseline)
            try check(evaluate(query, input, using: &execution), query: query)
            try require(observed.count > 2, "The actual query exposed no in-progress checkpoint.")
            // The same retained deterministic cube trace identifies its last observed
            // checkpoint. No new publication callback or production hook is introduced.
            for stop in [1, observed.count / 2, observed.count] {
                let observer = Checkpoints(stop: stop)
                let budget = try OriginalQueryBudget(checkpoint: { try observer.check() })
                var pending = try Shared.execution(budget)
                do { _ = try evaluate(query, input, using: &pending)
                    throw Failure(message: "Cancellation published a public volume result.") }
                catch {
                    guard let scalar = Shared.original(error) as? ExactScalarFailure,
                        case .cancelled = scalar else { throw error }
                }
                try require(observer.count == stop, "Cancellation escaped the actual caller checkpoint.")
                if stop == 1 {
                    try require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0,
                        "Entry cancellation consumed resources.")
                } else { try require(budget.snapshot.work > 0, "In-progress cancellation reset admitted work.") }
                print("VOLUME_CANCEL query=\(query.rawValue) checkpoint=\(stop)/\(observed.count)")
            }
        }
    }

    static func missingReferencesAndSourceLifetimeRemainExplicit() throws {
        func retainedResults() throws -> [Double] {
            var authored = Shared.cube()
            let retained = authored.model
            let shell = try shellID(authored)
            let vertex = VertexID(PortableIdentity128(high: 1, low: 1))
            authored.model.vertices[vertex] = Vertex(id: vertex, point: .init(x: 99, y: 0, z: 0))
            authored.model.geometry.surfaces.removeAll(where: { _ in true })
            authored.model.loops.removeAll(where: { _ in true })
            try require(retained.vertices[vertex]?.point == .origin && retained.geometry.surfaces.count == 6
                && retained.loops.count == 6, "Authored mutation changed the retained source.")
            var values: [Double] = []
            for query in [Query.all, .body, .shell] {
                var execution = try Shared.execution(OriginalQueryBudget())
                guard let result = try evaluate(query, (retained, authored.bodyID), using: &execution) else {
                    throw Failure(message: "A retained volume disappeared.")
                }
                values.append(result)
            }
            let missingBody = BodyID(PortableIdentity128(high: 8, low: 99))
            let missingShell = ShellID(PortableIdentity128(high: 7, low: 99))
            for isBody in [true, false] {
                var execution = try Shared.execution(OriginalQueryBudget())
                do {
                    if isBody { _ = try retained.volume(of: missingBody, tolerance: tolerance, using: &execution) }
                    else { _ = try retained.signedVolume(ofShell: missingShell, tolerance: tolerance, using: &execution) }
                    throw Failure(message: "A missing reference published a volume.")
                } catch {
                    let expected = isBody ? "Missing measurable body \(missingBody)." : "Missing measurable shell \(missingShell)."
                    guard let error = Shared.original(error) as? TopologyError,
                        error == .missingReference(expected) else { throw error }
                }
            }
            try require(retained.shells[shell] != nil, "The retained shell did not outlive authored mutation.")
            return values
        }
        let results = try retainedResults()
        try require(results.count == 3 && results.allSatisfy { abs($0 - 1) <= tolerance.distance },
            "A public result did not outlive its source/query owner.")
    }
}

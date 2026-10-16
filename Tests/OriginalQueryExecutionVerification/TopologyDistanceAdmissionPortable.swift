import CADCore
import CADGeometry
import CADTopology
import Synchronization

/// Actual point-distance domains, public provider dispatch and caller-owned lifetime boundaries.
@main
struct TopologyDistanceAdmissionPortable {
    struct Failure: Error { let message: String }
    private final class Checkpoints: Sendable {
        private let state = Mutex(0)
        private let stop: Int?
        init(stop: Int? = nil) { self.stop = stop }
        var count: Int { state.withLock { $0 } }
        func checkpoint() throws(ExactScalarFailure) {
            let ordinal = state.withLock { value in value += 1; return value }
            if ordinal == stop { throw .cancelled }
        }
    }
    static let firstPoint = Point3D(x: 4, y: 0, z: 0)
    static let secondPoint = Point3D(x: 4, y: 0, z: 3)
    static let options = BRepDistanceOptions(absoluteAccuracy: ModelingTolerance.standard.distance)

    static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw Failure(message: message) }
    }
    static func execution(_ budget: OriginalQueryBudget) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget, limits: try .init(maximumValueDepth: 32,
            maximumCoefficientDepth: 32, remainingSourceDepth: 16, maximumSubdivisionDepth: 32))
    }
    static func direct(using execution: inout OriginalQueryExecution) throws -> BRepDistanceQueryResult {
        try DefaultBRepDistanceQuery().distance(from: .point(firstPoint), to: .point(secondPoint),
            in: BRepModel(), options: options, tolerance: .standard, using: &execution)
    }
    static func query(_ budget: OriginalQueryBudget) throws -> BRepDistanceQueryResult {
        var admission = try execution(budget)
        try admission.consumeWork(7)
        return try direct(using: &admission)
    }
    static func retainedResult() throws -> BRepDistanceQueryResult {
        let budget = try OriginalQueryBudget()
        return try query(budget)
    }
    static func original(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return original(failure.originalError) }
        if let scalar = error as? ExactScalarFailure, case .admissionRejected(let cause) = scalar {
            return original(cause)
        }
        return error
    }
    static func resource(_ expected: ExactResource, _ operation: () throws -> Void) throws {
        do { try operation() }
        catch {
            guard let scalar = original(error) as? ExactScalarFailure,
                case .resourceLimit(let actual) = scalar, actual == expected else { throw error }
            return
        }
        throw Failure(message: "A resource-refused distance query published output.")
    }
    static func cancellation(_ operation: () throws -> Void) throws {
        do { try operation() }
        catch {
            guard let scalar = original(error) as? ExactScalarFailure, case .cancelled = scalar else { throw error }
            return
        }
        throw Failure(message: "A cancelled distance query published output.")
    }
    static func check(_ result: BRepDistanceQueryResult) throws {
        try require(result.lowerBound <= 3 && result.upperBound >= 3
            && result.upperBound - result.lowerBound <= options.absoluteAccuracy,
            "Point distance did not enclose its independent three-metre value.")
        try require(!result.witnesses.isEmpty, "Point distance lost its attained witnesses.")
        for witness in result.witnesses {
            try require(witness.firstSupport == .point(firstPoint) && witness.secondSupport == .point(secondPoint)
                && witness.firstPoint == firstPoint && witness.secondPoint == secondPoint,
                "The original point support or witness changed.")
            try require(witness.firstParameters.isEmpty && witness.secondParameters.isEmpty,
                "A point witness acquired invented parameters.")
        }
    }
    static func same(_ first: BRepDistanceQueryResult, _ second: BRepDistanceQueryResult) throws {
        try require(first.lowerBound == second.lowerBound && first.upperBound == second.upperBound
            && first.witnesses.count == second.witnesses.count, "Distance result changed across invocation ownership.")
        for (a, b) in zip(first.witnesses, second.witnesses) {
            try require(a.firstSupport == b.firstSupport && a.secondSupport == b.secondSupport
                && a.firstPoint == b.firstPoint && a.secondPoint == b.secondPoint
                && a.firstParameters == b.firstParameters && a.secondParameters == b.secondParameters,
                "Ordinary and admitted distance witnesses diverged.")
        }
    }
    static func publicWitnessAndRetention() throws {
        let provider: any BRepDistanceQuerying = DefaultBRepDistanceQuery()
        let ordinary = try provider.distance(from: .point(firstPoint), to: .point(secondPoint),
            in: BRepModel(), options: options, tolerance: .standard)
        let retained = try retainedResult()
        // Both invocation-local executions and Domain owners have left their scopes before these reads.
        try check(ordinary)
        try check(retained)
        try same(ordinary, retained)
        print("PASS Topology distance public witness and retained result")
    }
    static func resourceBoundaries() throws {
        let measured = try OriginalQueryBudget()
        let expected = try query(measured)
        let n = measured.snapshot
        try require(n.work > 7 && n.storageBytes > 0, "Point domains bypassed their caller's admission.")
        let exact = try OriginalQueryBudget(workLimit: n.work, storageByteLimit: n.storageBytes)
        let repeated = try query(exact)
        try same(expected, repeated)
        try require(exact.snapshot.work == n.work && exact.snapshot.storageBytes == n.storageBytes,
            "The measured exact distance boundary changed.")
        let work = try OriginalQueryBudget(workLimit: n.work - 1)
        try resource(.work) { _ = try query(work) }
        try require(work.snapshot.work <= n.work - 1, "A rejected work debit was committed.")
        let bytes = try OriginalQueryBudget(storageByteLimit: n.storageBytes - 1)
        try resource(.storage) { _ = try query(bytes) }
        try require(bytes.snapshot.storageBytes <= n.storageBytes - 1, "A rejected storage debit was committed.")
        let cumulative = try OriginalQueryBudget()
        var admission = try execution(cumulative)
        try admission.consumeWork(7)
        let first = try direct(using: &admission)
        let before = cumulative.snapshot
        let second = try direct(using: &admission)
        try same(first, second)
        try require(cumulative.snapshot.work > before.work && cumulative.snapshot.storageBytes > before.storageBytes,
            "A second distance invocation reset the retained caller's cumulative costs.")
        print("TOPOLOGY_DISTANCE work=\(n.work) bytes=\(n.storageBytes)")
        print("PASS Topology distance cumulative prefix and exact boundaries")
    }
    static func storageAndCheckpoints() throws {
        let zero = try OriginalQueryBudget(storageByteLimit: 0)
        try resource(.storage) { _ = try query(zero) }
        try require(zero.snapshot.storageBytes == 0, "Zero storage admitted a domain allocation.")
        let observer = Checkpoints()
        let baseline = try OriginalQueryBudget(checkpoint: { try observer.checkpoint() })
        _ = try query(baseline)
        try require(observer.count > 3, "The distance fixture has no inner and terminal checkpoint boundaries.")
        for stop in [1, max(2, observer.count / 2), observer.count] {
            let checkpoints = Checkpoints(stop: stop)
            let budget = try OriginalQueryBudget(checkpoint: { try checkpoints.checkpoint() })
            try cancellation { _ = try query(budget) }
            try require(checkpoints.count == stop, "Distance cancellation escaped its requested checkpoint.")
            if stop == 1 {
                try require(budget.snapshot.work == 0 && budget.snapshot.storageBytes == 0,
                    "Entry cancellation admitted paid work or an owner.")
            } else if stop == observer.count {
                try require(budget.snapshot.work == baseline.snapshot.work
                    && budget.snapshot.storageBytes == baseline.snapshot.storageBytes,
                    "Terminal cancellation changed the paid publication boundary.")
            } else {
                try require(budget.snapshot.work > 7 && budget.snapshot.work <= baseline.snapshot.work,
                    "Inner cancellation did not reach the actual distance operation.")
            }
        }
        print("PASS Topology distance zero storage and checkpoints")
    }
    static func loopInput() -> [SurfaceParameterCurve] {
        // The two authored lengths sqrt(2) and sqrt(5) require coefficient admission.
        [
            .polyline([.init(u: 0, v: 0), .init(u: 1, v: 1), .init(u: 3, v: 2)]),
            .polyline([.init(u: 3, v: 2), .init(u: 0, v: 0)]),
        ]
    }
    static func loopExecution(_ budget: OriginalQueryBudget, coefficientDepth: Int = 32) throws
        -> OriginalQueryExecution {
        OriginalQueryExecution(budget: budget, limits: try .init(maximumValueDepth: 32,
            maximumCoefficientDepth: coefficientDepth, remainingSourceDepth: 16,
            maximumSubdivisionDepth: 8))
    }
    static func loop(_ budget: OriginalQueryBudget, selectedDepth: Int? = 32,
        coefficientDepth: Int = 32, explicitPeriods: Bool = false) throws
        -> [SurfaceParameterLoopUnwrapper.UnwrappedCurve] {
        var admission = try loopExecution(budget, coefficientDepth: coefficientDepth)
        try admission.consumeWork(11)
        let surface = Surface3D.plane(Plane3D(origin: .origin, normal: .unitZ))
        let tolerance = ModelingTolerance.standard
        if explicitPeriods {
            return try SurfaceParameterLoopUnwrapper().unwrap(loopInput(),
                uPeriod: nil, vPeriod: nil,
                uClosureTolerance: tolerance.distance * 8, vClosureTolerance: tolerance.distance * 8,
                on: surface, tolerance: tolerance, context: "Portable authored polyline loop",
                maximumSubdivisionDepth: 8, remainingSourceDepth: 16,
                maximumAlgebraicDepth: selectedDepth, using: &admission)
        }
        return try SurfaceParameterLoopUnwrapper().unwrap(loopInput(), on: surface,
            tolerance: tolerance, context: "Portable authored polyline loop",
            maximumSubdivisionDepth: 8, remainingSourceDepth: 16,
            maximumAlgebraicDepth: selectedDepth, using: &admission)
    }
    static func loopCapabilities() throws {
        let budget = try OriginalQueryBudget()
        let result = try loop(budget)
        let input = loopInput()
        try require(result.map { $0.curve } == input && result.allSatisfy { $0.uShift == 0 && $0.vShift == 0 },
            "Selected loop algebra changed the authored curves or invented a periodic shift.")
        for index in result.indices {
            let next = result[(index + 1) % result.count]
            try require(abs(result[index].chartEnd.u - next.chartStart.u) <= ModelingTolerance.standard.distance * 8
                && abs(result[index].chartEnd.v - next.chartStart.v) <= ModelingTolerance.standard.distance * 8,
                "The original polyline junction was not preserved.")
        }
        let explicit = try loop(OriginalQueryBudget(), explicitPeriods: true)
        try require(explicit == result, "Bounded loop overloads diverged on the same original source.")
        do {
            _ = try loop(OriginalQueryBudget(), selectedDepth: nil)
            throw Failure(message: "An explicit nil algebra capability published a loop.")
        } catch {
            guard let failure = original(error) as? KernelError,
                failure.phase == .geometry && failure.code == .unsupportedCapability
                && failure.message == "Original Euclidean polyline bounds require caller algebra admission." else {
                throw error
            }
        }
        for (selected, ambient) in [(0, 32), (32, 0)] {
            try resource(.coefficientDepth) {
                _ = try loop(OriginalQueryBudget(), selectedDepth: selected, coefficientDepth: ambient)
            }
        }
        try require(budget.snapshot.work > 11 && budget.snapshot.storageBytes > 0,
            "Original loop bounds bypassed the caller's numeric admission.")
        print("PASS Topology loop selected nil and independent algebra caps")
    }
    static func loopResourceBoundaries() throws {
        let measured = try OriginalQueryBudget()
        let expected = try loop(measured, explicitPeriods: true)
        let n = measured.snapshot
        let exact = try OriginalQueryBudget(workLimit: n.work, storageByteLimit: n.storageBytes)
        let repeated = try loop(exact, explicitPeriods: true)
        try require(repeated == expected && exact.snapshot.work == n.work
            && exact.snapshot.storageBytes == n.storageBytes, "The measured loop boundary changed.")
        let work = try OriginalQueryBudget(workLimit: n.work - 1)
        try resource(.work) { _ = try loop(work, explicitPeriods: true) }
        try require(work.snapshot.work <= n.work - 1, "Loop work refusal committed its rejected debit.")
        let bytes = try OriginalQueryBudget(storageByteLimit: n.storageBytes - 1)
        try resource(.storage) { _ = try loop(bytes, explicitPeriods: true) }
        try require(bytes.snapshot.storageBytes <= n.storageBytes - 1,
            "Loop storage refusal committed its rejected debit.")
        let cancelled = try OriginalQueryBudget(checkpoint: { throw ExactScalarFailure.cancelled })
        try cancellation { _ = try loop(cancelled, explicitPeriods: true) }
        try require(cancelled.snapshot.work == 0 && cancelled.snapshot.storageBytes == 0,
            "Entry cancellation admitted loop work or storage.")
        print("TOPOLOGY_LOOP work=\(n.work) bytes=\(n.storageBytes)")
        print("PASS Topology loop cumulative exact boundaries and cancellation")
    }
    static func main() throws {
        try publicWitnessAndRetention()
        try resourceBoundaries()
        try storageAndCheckpoints()
        try loopCapabilities()
        try loopResourceBoundaries()
        print("PASS Topology distance portable all")
    }
}

#if canImport(Darwin)
import Darwin
#elseif canImport(WASILibc)
import WASILibc
#endif
import Synchronization
import CADCore
@testable import CADGeometry
@main struct RevolutionAxisFiberAcceptance {
 struct Failure:Error { let line:Int }
 static func require(_ value:Bool,line:Int = #line) throws { if !value { throw Failure(line:line) } }
    final class Counter: Sendable {
        struct State: Sendable { var work = 0; var bytes = 0 }
        private let state = Mutex(State())
        let maximumWork: Int
        let maximumBytes: Int
        let cancelAt: Int?
        let cancelStorageAt: Int?
        init(work: Int = 8_388_608, bytes: Int = Int.max, cancelAt: Int? = nil,
            cancelStorageAt: Int? = nil) {
            maximumWork = work; maximumBytes = bytes; self.cancelAt = cancelAt
            self.cancelStorageAt = cancelStorageAt
        }
        func consume(_ depth: Int) throws {
            let reached = try state.withLock { state in
                guard state.work < maximumWork else { throw ExactScalarFailure.resourceLimit(.work) }
                state.work += 1; return state.work
            }
            if reached == cancelAt { throw CancellationError() }
        }
        func retain(_ bytes: Int) throws {
            let reached = try state.withLock { state in
                let next = state.bytes.addingReportingOverflow(bytes)
                guard bytes >= 0, !next.overflow, next.partialValue <= maximumBytes else {
                    throw ExactScalarFailure.resourceLimit(.storage)
                }
                state.bytes = next.partialValue; return state.bytes
            }
            if reached == cancelStorageAt { withUnsafeCurrentTask { $0?.cancel() } }
        }
        var totals: State { state.withLock { $0 } }
    }
    static func logCount(_ label: StaticString, _ value: Int) {
        print(label, terminator: ": ")
        var divisor = 1
        while divisor <= value / 10 { divisor *= 10 }
        repeat { putchar(Int32(48 + value / divisor % 10)); divisor /= 10 } while divisor > 0
        putchar(10); fflush(nil)
    }
    static func input() throws -> (Curve3D, Surface3D, CurveSurfaceIntersectionOptions) {
            var admission = ExactScalarLedger(limits: try .init(work: 8_388_608,
                storageBytes: 8_388_608, valueDepth: 32, coefficientDepth: 32))
            let angularBound = 2 * Double.pi
            let surface = try ExactScalarNumericAccess.withAdmission(&admission) { usage in
                let raw = BSplineCurve3D(degree: 1, knots: [0,0,1,1],
                    controlPoints: [.origin, .init(x:1,y:0,z:0)], weights: [1,2])
                let generator = try OriginalCurveRootSpan3D(source: .bSpline(raw),
                    start: .authored(0), end: .authored(1), nativeSpanIndex: 1,
                    maximumParameterWidth: ModelingTolerance.standard.relative, maximumSubdivisionDepth: 0,
                    tolerance: .standard, storageByteStride: MemoryLayout<UInt32>.stride, usage: &usage,
                    maximumSpanCount: 2, remainingSourceDepth: 0, maximumAlgebraicDepth: 0).reversed()
                return try OriginalRevolutionSurface3D(generator: generator, axisOrigin: .origin,
                    axisDirection: .init(x:0,y:0,z:2), uDomain: .closed(-angularBound,angularBound),
                    tolerance: .standard, usage: &usage)
            }.value
            let curve = Curve3D.line(.init(origin: .origin, direction: .unitZ))
            let host = Surface3D.procedural(.originalRevolution(surface))
            var options = CurveSurfaceIntersectionOptions()
            options.curveRange = try .init(lower: -1, upper: 1)
            options.surfaceURange = try .init(lower: -angularBound, upper: angularBound)
            options.surfaceVRange = try .init(lower: 0, upper: 1)

        return (curve, host, options)
    }
    static func admitted(_ curve: Curve3D, _ host: Surface3D, _ options: CurveSurfaceIntersectionOptions,
        _ counter: Counter, sourceDepth: Int = 8, algebraicDepth: Int = 32) throws -> CurveSurfaceIntersectionResult {
        try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: host,
            options: options, tolerance: .standard, maximumSpanCount: 262_144,
            maximumSubdivisionDepth: 8, remainingSourceDepth: sourceDepth,
            consumeWork: { try counter.consume($0) }, consumeStorage: { try counter.retain($0) },
            maximumAlgebraicDepth: algebraicDepth)
    }
    static func full(_ result: CurveSurfaceIntersectionResult) throws {
        guard let geometry = result.originalRevolutionAxisRelation else { throw Failure(line: #line) }
        try RevolutionAxisFiberOracle.verify(geometry)
    }
    static func boundedFailure(_ body: () throws -> Void) throws {
        do { try body(); throw Failure(line: #line) }
        catch let error as KernelError { try require(error.code == .resourceLimitExceeded) }
    }
    static func run() async throws {
        let (curve, host, options) = try input()
        let angularBound = 2 * Double.pi
#if hasFeature(Embedded)
        let group = getenv("CAD_PROOF_GROUP").map { String(cString: $0) } ?? "complete"
#else
        let group = CommandLine.arguments[1]
#endif
        func query(_ selected: CurveSurfaceIntersectionOptions) throws -> CurveSurfaceIntersectionResult {
            try DefaultCurveSurfaceIntersector().intersectionResult(curve: curve, surface: host,
                options: selected, tolerance: .standard)
        }
        if group == "complete" {
            let result = try query(options)
            guard let geometry = result.originalRevolutionAxisRelation else { throw Failure(line: #line) }
            try require(result.representation == .exactRelation && result.points.isEmpty && result.overlaps.isEmpty)
            try require(!geometry.isEmpty && geometry.hasPositiveDimensionalSolutions && !geometry.hasPositiveDimensionalImage)
            try RevolutionAxisFiberOracle.verify(geometry)
            do {
                _ = try DefaultCurveSurfaceIntersector().intersections(curve: curve, surface: host,
                    options: options, tolerance: .standard)
                throw Failure(line: #line)
            } catch let error as KernelError {
                try require(error.code == .nonDiscreteIntersection)
            }
            print("PASS complete ordinary rich axis fiber and bare positive-parameter refusal")
        } else if group == "empty" {
            for control in 0..<3 {
                var selected = options
                if control == 0 { selected.surfaceVRange = try .init(lower: 0, upper: 0.5) }
                if control == 1 { selected.curveRange = try .init(lower: 0.5, upper: 1) }
                if control == 2 { selected.surfaceURange = try .init(lower: angularBound + 1, upper: angularBound + 2) }
                let result = try query(selected)
                guard let geometry = result.originalRevolutionAxisRelation else { throw Failure(line: #line) }
                try require(result.representation == .exactRelation && result.points.isEmpty && result.overlaps.isEmpty)
                try require(geometry.isEmpty && !geometry.hasPositiveDimensionalSolutions && !geometry.hasPositiveDimensionalImage)
                for pair in geometry.pairs {
                    try require(pair.original.relation.selection.cells.isEmpty && pair.geometry.strata.isEmpty)
                }
            }
            print("PASS full-domain empty V, T, and outside-support U controls")
        } else if group == "resources" {
            let baseline = Counter()
            try full(admitted(curve, host, options, baseline))
            let totals = baseline.totals
            try require(totals.work > 2 && totals.work <= 8_388_608 && totals.bytes > 0)
            logCount("QUERY_WORK", totals.work); logCount("QUERY_STORAGE", totals.bytes)
            let exact = Counter(work: totals.work, bytes: totals.bytes)
            try full(admitted(curve, host, options, exact))
            try require(exact.totals.work == totals.work && exact.totals.bytes == totals.bytes)
            for cap in [1, totals.work / 2, totals.work - 1] {
                let counter = Counter(work: cap)
                try boundedFailure { _ = try admitted(curve, host, options, counter) }
                try require(counter.totals.work == cap)
            }
            try boundedFailure { _ = try admitted(curve, host, options, Counter(bytes: totals.bytes - 1)) }
            for depth in [0, 1] {
                try boundedFailure { _ = try admitted(curve, host, options, Counter(), sourceDepth: depth) }
            }
            try full(admitted(curve, host, options, Counter(), sourceDepth: 2))
            try boundedFailure { _ = try admitted(curve, host, options, Counter(), algebraicDepth: 0) }
            for kind in 0..<2 {
                var selected = options
                if kind == 0 { selected.maximumCandidateCount = 0 }
                else { selected.maximumPolynomialDegree = 0 }
                try boundedFailure { _ = try admitted(curve, host, selected, Counter()) }
            }
            for tick in [1, totals.work / 2] {
                let counter = Counter(cancelAt: tick)
                do { _ = try admitted(curve, host, options, counter); throw Failure(line: #line) }
                catch is CancellationError { }
                try require(counter.totals.work == tick)
            }
            print("PASS exact work/storage limits, one-unit refusals, source/algebraic depth, degree/candidates and callback cancellation")
        } else if group == "cancel-entry" {
            let counter = Counter()
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try admitted(curve, host, options, counter); throw Failure(line: #line) }
            catch is CancellationError { }
            try require(counter.totals.work == 0 && counter.totals.bytes == 0)
            print("PASS task cancellation before work and storage")
        } else if group == "cancel-final" || group == "cancel-empty" {
            var selected = options
            if group == "cancel-empty" { selected.surfaceVRange = try .init(lower: 0, upper: 0.5) }
            let baseline = Counter()
            let result = try admitted(curve, host, selected, baseline)
            if group == "cancel-empty" {
                guard let geometry = result.originalRevolutionAxisRelation else { throw Failure(line: #line) }
                try require(geometry.isEmpty)
            } else { try full(result) }
            let counter = Counter(cancelStorageAt: baseline.totals.bytes)
            do { _ = try admitted(curve, host, selected, counter); throw Failure(line: #line) }
            catch is CancellationError { }
            try require(counter.totals.bytes == baseline.totals.bytes)
            print("PASS task cancellation at final result allocation before publication")
        } else if group == "lifetime" {
            let retained: CurveSurfaceIntersectionResult
            do {
                let (localCurve, localHost, localOptions) = try input()
                retained = try admitted(localCurve, localHost, localOptions, Counter())
            }
            guard let geometry = retained.originalRevolutionAxisRelation,
                case .bSpline(let original) = geometry.originalDomain.source.original.original.generator.source else {
                throw Failure(line: #line)
            }
            var changed = original; changed.controlPoints[0].x = 7
            try require(original.controlPoints[0].x == 0 && changed.controlPoints[0].x == 7)
            try full(retained)
            try await withThrowingTaskGroup(of: Void.self) { readers in
                for _ in 0..<2 { readers.addTask { try full(retained) } }
                try await readers.waitForAll()
            }
            print("PASS detached source/result lifetime, source COW and concurrent independent exact readers")
        } else { throw Failure(line: #line) }
    }
    static func main() async {
        do { try await run() }
        catch {
            print("FAIL revolution axis public acceptance")
#if !hasFeature(Embedded)
            print(error)
#endif
            exit(1)
        }
    }
}

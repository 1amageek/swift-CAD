import CADCore
import CADGeometry
@testable import CADModeling
import Synchronization
import Testing

@Suite("Original authored-U drafted boundary support")
struct OriginalAuthoredDraftedBoundaryPlanarityTests {
    private enum Failure: Error, Equatable { case work, storage }
    private final class Ledger: Sendable {
        private struct State {
            var work = 0, bytes = 0, workCalls = 0, storageCalls = 0
        }
        private let state = Mutex(State())
        private let maximumWork: Int
        private let maximumBytes: Int
        private let cancelAtWorkCall: Int?
        private let cancelAtStorageCall: Int?
        init(maximumWork: Int = 10_000_000, maximumBytes: Int = 40_000_000,
            cancelAtWorkCall: Int? = nil, cancelAtStorageCall: Int? = nil) {
            self.maximumWork = maximumWork; self.maximumBytes = maximumBytes
            self.cancelAtWorkCall = cancelAtWorkCall; self.cancelAtStorageCall = cancelAtStorageCall
        }
        func work(_ count: Int) throws {
            let cancel = try state.withLock { value in
                guard count >= 0, count <= maximumWork - value.work else { throw Failure.work }
                value.work += count; value.workCalls += 1
                return value.workCalls == cancelAtWorkCall
            }
            if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        }
        func storage(_ count: Int) throws {
            let cancel = try state.withLock { value in
                guard count >= 0, count <= maximumBytes - value.bytes else { throw Failure.storage }
                value.bytes += count; value.storageCalls += 1
                return value.storageCalls == cancelAtStorageCall
            }
            if cancel { withUnsafeCurrentTask { $0?.cancel() } }
        }
        var counts: (work: Int, bytes: Int) { state.withLock { ($0.work, $0.bytes) } }
        var calls: (work: Int, storage: Int) { state.withLock { ($0.workCalls, $0.storageCalls) } }
    }
    private let delta = 1e-12
    private let length = 1_073_741_824.0
    private let tolerance = ModelingTolerance.standard
    private var plane: Plane3D {
        .init(origin: .origin, normal: .unitZ, uDirection: .init(x: 1, y: 0, z: delta))
    }
    private func admission(_ ledger: Ledger, depth: Int = 4) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try OriginalQueryBudget(
            consumeWorkUnits: { try ledger.work($0) }, consumeStorageBytes: { try ledger.storage($0) }),
            limits: try .init(maximumValueDepth: 0, maximumCoefficientDepth: 0,
                remainingSourceDepth: 0, maximumSubdivisionDepth: depth, maximumSpans: 1))
    }
    private func originalCause(_ error: any Error) -> any Error {
        if let failure = error as? OriginalQueryFailure { return originalCause(failure.originalError) }
        if case ExactScalarFailure.admissionRejected(let cause) = error { return originalCause(cause) }
        return error
    }
    private func isCancellation(_ error: any Error) -> Bool {
        let cause = originalCause(error)
        if case ExactScalarFailure.cancelled = cause { return true }
        return cause is CancellationError
    }
    private func traversal(_ points: [Point3D]) throws -> OriginalCurveRootSpan3D {
        let native = BSplineCurve3D(degree: 1, knots: [-2, -2, 4, 4], controlPoints: points, weights: [1, 1])
        var usage = try admission(Ledger())
        return try .init(source: .bSpline(native), start: .authored(-2), end: .authored(4),
            nativeSpanIndex: 1, maximumParameterWidth: tolerance.relative, maximumSubdivisionDepth: 0,
            tolerance: tolerance, usage: &usage,
            maximumSpanCount: 1, remainingSourceDepth: 0, maximumAlgebraicDepth: 0)
    }
    private func chartTraversal() throws -> OriginalCurveRootSpan3D {
        try traversal([.init(x: length / 2, y: 0, z: length * delta / 2),
            .init(x: length, y: 0, z: length * delta)])
    }
    private func wrongTraversal() throws -> OriginalCurveRootSpan3D {
        try traversal([.init(x: length / 2, y: 0, z: 0), .init(x: length, y: 0, z: 0)])
    }
    private func validate(_ source: OriginalCurveRootSpan3D, using admission: inout OriginalQueryExecution) throws {
        try OriginalDraftedBoundaryPlanarity().validate(source, on: plane, tolerance: tolerance, using: &admission)
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredChartNativeBoundaryPassesWholeOriginalDomain() throws {
        try plane.validate(tolerance: tolerance)
        let source = try chartTraversal()
        let retained = source
        let ledger = Ledger()
        var caller = try admission(ledger)
        try validate(source, using: &caller)
        try validate(source.reversed(), using: &caller)
        #expect(source == retained && source.source == retained.source)
        #expect(source.nativeSpanIndex == 1 && source.start == .authored(-2) && source.end == .authored(4))
        #expect(ledger.counts.work > 0 && ledger.counts.bytes > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func rawNormalPlaneBoundaryFailsAuthoredChartAllowance() throws {
        let source = try wrongTraversal()
        // Both endpoints, and every interior point, are more than 500 distance
        // allowances from the authored chart while their raw z is identically zero.
        #expect(length * delta / 2 > 500 * tolerance.distance)
        let ledger = Ledger()
        var caller = try admission(ledger)
        do {
            try validate(source, using: &caller)
            Issue.record("A raw-normal plane curve outside the authored chart was admitted.")
        } catch let error as GeometryConversionError {
            guard case .invalidInput = error else { throw error }
        }
        #expect(ledger.counts.work > 0 && ledger.counts.bytes > 0)
        #expect(throws: GeometryConversionError.self) { try validate(source.reversed(), using: &caller) }
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredPlanarityUsesIndependentCallerWorkAndStorage() throws {
        let source = try chartTraversal()
        let successful = Ledger()
        var full = try admission(successful)
        try validate(source, using: &full)
        let counts = successful.counts
        #expect(counts.work > 0 && counts.bytes > 0)
        let work = Ledger(maximumWork: counts.work - 1)
        var workCaller = try admission(work)
        #expect { try validate(source, using: &workCaller) } throws: { originalCause($0) as? Failure == .work }
        #expect(work.counts.bytes > 0)
        let storage = Ledger(maximumBytes: counts.bytes - 1)
        var storageCaller = try admission(storage)
        #expect { try validate(source, using: &storageCaller) } throws: { originalCause($0) as? Failure == .storage }
        #expect(storage.counts.work > 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredPlanarityUnresolvedClosedDomainRemainsDepthFailure() throws {
        let source = try traversal([.origin, .init(x: 0, y: 0, z: 2 * tolerance.distance)])
        let ledger = Ledger()
        var caller = try admission(ledger, depth: 0)
        do {
            try validate(source, using: &caller)
            Issue.record("An unresolved whole-domain section proof returned success at depth zero.")
        } catch let error as GeometryConversionError {
            guard case .resourceLimitExceeded = error else { throw error }
        }
        #expect(ledger.counts.work > 0 && ledger.counts.bytes > 0)
    }

    private func terminalCallbackCancellation(_ source: OriginalCurveRootSpan3D, boundary: String) async throws {
        let measured = Ledger()
        var measuring = try admission(measured)
        try validate(source, using: &measuring)
        let calls = measured.calls
        #expect(calls.work > 0 && calls.storage > 0)
        let ledger = Ledger(cancelAtWorkCall: boundary == "work" ? calls.work : nil,
            cancelAtStorageCall: boundary == "storage" ? calls.storage : nil)
        let task = Task {
            var caller = try admission(ledger)
            // Cancellation happens after the selected callback's ordinary
            // accounting and outside the shared ledger lock; it returns normally.
            try validate(source, using: &caller)
        }
        await #expect { _ = try await task.value } throws: { isCancellation($0) }
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["work", "storage"])
    func authoredPlanarityExactTerminalCallbackCancellationPropagates(boundary: String) async throws {
        try await terminalCallbackCancellation(chartTraversal(), boundary: boundary)
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["work", "storage"])
    func authoredPlanarityCoverTerminalCallbackCancellationPropagates(boundary: String) async throws {
        // The nonzero support polynomial enters the closed interval cover; the
        // entire curve stays strictly inside the existing distance allowance.
        let source = try traversal([.init(x: 0, y: 0, z: tolerance.distance / 4),
            .init(x: 0, y: 1, z: tolerance.distance / 4)])
        try await terminalCallbackCancellation(source, boundary: boundary)
    }

    @Test(.timeLimit(.minutes(1)))
    func authoredPlanarityCancellationPropagates() async throws {
        let source = try chartTraversal()
        let ledger = Ledger()
        let task = Task {
            var caller = try admission(ledger)
            withUnsafeCurrentTask { $0?.cancel() }
            try validate(source, using: &caller)
        }
        await #expect { _ = try await task.value } throws: { isCancellation($0) }
        #expect(ledger.counts.work == 0 && ledger.counts.bytes == 0)
    }
}

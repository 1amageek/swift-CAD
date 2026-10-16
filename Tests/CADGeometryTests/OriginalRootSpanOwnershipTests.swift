import CADCore
import Foundation
import Synchronization
import Testing
@testable import CADGeometry

@Suite("Original traversal immutable ownership")
struct OriginalRootSpanOwnershipTests {
    private let tolerance = ModelingTolerance.standard

    private func allowance(storage: Int = 1_073_741_824,
        observeStorage: (@Sendable (Int) throws -> Void)? = nil) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try OriginalQueryBudget(workLimit: 80_000_000,
            storageByteLimit: storage, cellLimit: 80_000_000, cellVisitWorkUnits: 0,
            consumeStorageBytes: observeStorage),
            limits: try .init(maximumValueDepth: 64, maximumCoefficientDepth: 64, maximumCells: 80_000_000))
    }

    private func traversal(usage: inout OriginalQueryExecution) throws -> OriginalCurveRootSpan3D {
        try .init(source: .bSpline(.init(degree: 1, knots: [0,0,1,1],
            controlPoints: [.origin, .init(x: 1,y: 0,z: 0)])),
            start: .authored(0), end: .authored(1), nativeSpanIndex: 1,
            maximumParameterWidth: tolerance.relative, maximumSubdivisionDepth: 0,
            tolerance: tolerance, usage: &usage, maximumSpanCount: 1,
            remainingSourceDepth: 0, maximumAlgebraicDepth: 32)
    }

    private func query(_ span: OriginalCurveRootSpan3D, station: Double)
        throws -> OriginalCurveFirstOrderJet {
        var usage = try allowance()
        return try span.preparedFirstOrder(over: .init(lower: station, upper: station),
            tolerance: tolerance, maximumSpanCount: 1, maximumSubdivisionDepth: 0,
            remainingSourceDepth: 0, using: &usage)
    }

    @Test(.timeLimit(.minutes(1)))
    func copiedAndReversedViewsRetainDirectedLawAcrossWorkers() async throws {
        let retained: OriginalCurveRootSpan3D
        do {
            var usage = try allowance()
            retained = try traversal(usage: &usage).reversed()
            let before = usage.budget.snapshot.storageBytes
            #expect(retained.reversed().reversed() == retained)
            #expect(usage.budget.snapshot.storageBytes == before)
        }
        #expect(retained.start == .authored(1))
        #expect(retained.end == .authored(0))
        #expect(Set([retained, retained.reversed().reversed()]).count == 1)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let reversed = try query(retained, station: 0.25)
                    #expect(reversed.position.x.lower <= 0.75 && reversed.position.x.upper >= 0.75)
                    #expect(reversed.firstDerivative.x.lower <= -1 && reversed.firstDerivative.x.upper >= -1)
                    let forward = try query(retained.reversed(), station: 0.25)
                    #expect(forward.position.x.lower <= 0.25 && forward.position.x.upper >= 0.25)
                    #expect(forward.firstDerivative.x.lower <= 1 && forward.firstDerivative.x.upper >= 1)
                }
            }
            try await group.waitForAll()
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func constructorRefusesTheFinalRetainedPayloadCapacity() throws {
        var admitted = try allowance()
        _ = try traversal(usage: &admitted)
        let total = admitted.budget.snapshot.storageBytes
        #expect(total > 0)
        var insufficient = try allowance(storage: total - 1)
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) { _ = try traversal(usage: &insufficient) }
        #expect(insufficient.budget.snapshot.storageBytes < total)
    }

    @Test(.timeLimit(.minutes(1)))
    func nativeCodecReconstructsReversedLawOnItsOriginalLedger() throws {
        var usage = try allowance()
        let original = try traversal(usage: &usage).reversed()
        let bytes = try JSONEncoder().encode(original)
        func decoder(storage: Int) throws -> (JSONDecoder, NativeRationalSourceDecodingContext) {
            let budget = try NativeRationalSourceDecodingContext(maximumWork: 80_000_000,
                maximumCells: 80_000_000, maximumStorage: storage, maximumDepth: 64, operationCheck: {})
            let decoder = JSONDecoder()
            decoder.userInfo[NativeRationalSourceDecodingContext.key] = budget
            decoder.userInfo[OriginalAffineWordDecodingContext.maximumSourceDepthKey] = 64
            decoder.userInfo[OriginalAffineWordDecodingContext.maximumCurveSubdivisionDepthKey] = 0
            decoder.userInfo[OriginalAffineWordDecodingContext.maximumAlgebraicDepthKey] = 32
            decoder.userInfo[OriginalAffineWordDecodingContext.toleranceKey] = tolerance
            return (decoder, budget)
        }
        let (admittedDecoder, budget) = try decoder(storage: 268_435_456)
        let decoded = try admittedDecoder.decode(OriginalCurveRootSpan3D.self, from: bytes)
        #expect(decoded == original)
        #expect(Set([decoded, original]).count == 1)
        let value = try query(decoded, station: 0.25)
        #expect(value.position.x.lower <= 0.75 && value.position.x.upper >= 0.75)
        let total = try budget.snapshot().storage
        let (insufficientDecoder, _) = try decoder(storage: total - 1)
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) {
            _ = try insufficientDecoder.decode(OriginalCurveRootSpan3D.self, from: bytes)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func queryCapabilityRebindingAdmitsItsNewPayload() throws {
        var construction = try allowance()
        let original = try traversal(usage: &construction).reversed()
        func rebound(_ budget: inout OriginalQueryExecution) throws -> OriginalCurveRootSpan3D {
            try original.admittingQueryAlgebra(16, tolerance: tolerance,
                maximumSubdivisionDepth: 0, remainingSourceDepth: 0,
                using: &budget)
        }
        var admitted = try allowance()
        let selected = try rebound(&admitted)
        #expect(selected == original)
        #expect(selected.maximumAlgebraicDepth == 16)
        #expect(original.maximumAlgebraicDepth == 32)
        #expect(selected.start == .authored(1) && selected.end == .authored(0))
        let value = try query(selected, station: 0.25)
        #expect(value.position.x.lower <= 0.75 && value.position.x.upper >= 0.75)
        let total = admitted.budget.snapshot.storageBytes
        #expect(total > 0)
        var insufficient = try allowance(storage: total - 1)
        geometryTestExpectFailure({ geometryTestKernelFailure($0) != nil }) { _ = try rebound(&insufficient) }
    }

    @Test(.timeLimit(.minutes(1)))
    func finalPayloadAdmissionCancellationPreventsPublication() async throws {
        let reservations = Mutex<[Int]>([])
        var baseline = try allowance(observeStorage: { bytes in reservations.withLock { $0.append(bytes) } })
        _ = try traversal(usage: &baseline)
        let lastOrdinal = reservations.withLock { $0.count }
        #expect(lastOrdinal > 0)
        let count = Mutex(0)
        let operation = Task {
            var budget = try allowance(observeStorage: { _ in
                let isLast = count.withLock { count in count += 1; return count == lastOrdinal }
                if isLast { withUnsafeCurrentTask { $0?.cancel() } }
            })
            return try traversal(usage: &budget)
        }
        do {
            _ = try await operation.value
            Issue.record("A final payload admission callback cancelled but published a traversal.")
        } catch where geometryTestIsCancelled(error) {
            #expect(count.withLock { $0 } == lastOrdinal)
        }
    }

}

import CADCore
import CADGeometry
import CADModeling
import CADTopology
import Synchronization
import Testing
@testable import CADKernel

@Suite("Kernel diagnostic failure classification", .timeLimit(.minutes(1)))
struct KernelDiagnosticFailureClassificationTests {
    private final class WorkCounter: Sendable {
        private let state = Mutex(0)
        func add(_ units: Int) { state.withLock { $0 += units } }
        var value: Int { state.withLock { $0 } }
    }

    private func execution(work: Int = 8_388_608) throws -> OriginalQueryExecution {
        OriginalQueryExecution(budget: try .init(workLimit: work, storageByteLimit: 268_435_456),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .boundary, entry: .admitted, stage: .request))
    }

    private func emptyGraph() -> BooleanIntersectionGraph {
        .init(facePairs: [], boundaryContacts: [], faceIntersections: [])
    }


    private func containsDiagnostic(_ text: String, _ needle: String) -> Bool {
        if needle.isEmpty { return true }
        for index in text.utf8.indices {
            if text.utf8[index...].starts(with: needle.utf8) { return true }
        }
        return false
    }

    private func assertLowerWorkFailure(_ error: any Error, budget: OriginalQueryBudget,
        stage: OriginalQueryFailureContext.Stage, diagnostic: String) throws {
        let failure = try #require(error as? OriginalQueryFailure)
        #expect(budget.snapshot.work == 1)
        let scalar = try #require(failure.originalError as? ExactScalarFailure)
        guard case .resourceLimit(.work) = scalar else {
            Issue.record("The actual lower work rejection was replaced by another cause.")
            return
        }
        #expect(failure.kernelFailure.code == .resourceLimitExceeded)
        #expect(failure.context.operation == .boundary)
        #expect(failure.context.entry == .admitted)
        #expect(failure.context.stage == stage)
        #expect(failure.context.resource?.axis == .work)
        #expect(containsDiagnostic(failure.kernelFailure.message, diagnostic))
    }

    @Test
    func emptyGraphRemainsAGenuineEmptySplit() throws {
        var execution = try execution()
        let graph = emptyGraph()
        let result = try DefaultBooleanUVFaceSplitter().splitGraph(intersectionGraph: graph,
            model: BRepModel(), tolerance: .standard, using: &execution)
        #expect(result.splits.isEmpty)
        #expect(execution.budget.snapshot.work > 1)
        let ordinary = try DefaultBooleanUVFaceSplitter().splitGraph(intersectionGraph: graph,
            model: BRepModel(), tolerance: .standard)
        #expect(ordinary == result)
    }

    @Test
    func splitGraphLowerWorkRefusalRetainsItsOriginalClassification() throws {
        var execution = try execution(work: 1)
        do {
            _ = try DefaultBooleanUVFaceSplitter().splitGraph(intersectionGraph: emptyGraph(),
                model: BRepModel(), tolerance: .standard, using: &execution)
            Issue.record("Split graph validation escaped its nonzero caller work boundary.")
        } catch {
            try assertLowerWorkFailure(error, budget: execution.budget, stage: .refinement,
                diagnostic: "input graph validation")
        }
    }

    @Test
    func crossingLinesRetainTheirNonemptyContact() throws {
        try KernelTrimDiagnosticFailureChecks.crossingLinesRetainTheirNonemptyContact()
    }

    @Test
    func trimContactLowerWorkRefusalRetainsItsOriginalClassification() throws {
        try KernelTrimDiagnosticFailureChecks.trimContactLowerWorkRefusalRetainsItsOriginalClassification()
    }

    @Test(arguments: [true, false])
    func lowerCallerCancellationRetainsItsOriginalCause(splitGraph: Bool) throws {
        if !splitGraph {
            try KernelTrimDiagnosticFailureChecks.lowerTrimCallerCancellationRetainsItsOriginalCause()
            return
        }
        let observed = WorkCounter()
        let budget = try OriginalQueryBudget(workLimit: 8_388_608, storageByteLimit: 268_435_456,
            consumeWorkUnits: { units in observed.add(units) },
            checkpoint: {
                if observed.value >= 1 { throw CancellationError() }
            })
        var execution = OriginalQueryExecution(budget: budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 16, maximumSubdivisionDepth: 32),
            context: .init(operation: .boundary, entry: .admitted, stage: .request))
        do {
            _ = try DefaultBooleanUVFaceSplitter().splitGraph(intersectionGraph: emptyGraph(),
                model: BRepModel(), tolerance: .standard, using: &execution)
            Issue.record("The actual lower diagnostic boundary ignored cancellation.")
        } catch {
            #expect(budget.snapshot.work == 1)
            #expect(observed.value == 1)
            #expect(error is CancellationError)
        }
    }
}

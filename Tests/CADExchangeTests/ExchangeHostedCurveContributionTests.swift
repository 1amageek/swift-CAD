import Testing
import CADCore
import CADGeometry
@testable import CADExchange

@Suite("Hosted curve retained contribution", .timeLimit(.minutes(1)))
struct ExchangeHostedCurveContributionTests {
    private func execution() throws -> OriginalQueryExecution {
        try .init(budget: OriginalQueryBudget(),
            limits: .init(maximumValueDepth: 32, maximumCoefficientDepth: 32))
    }

    private func issue(workLimit: Int? = nil, using execution: inout OriginalQueryExecution)
        throws -> (source: ExchangeHostedCurveConversionSource, handle: OriginalQueryContributionHandle) {
        let handle = try execution.makeContributionHandle(workLimit: workLimit)
        let source = try execution.withContributionScope(handle) { execution in
            try ExchangeHostedCurveConversionSource(
                surface: .plane(.init(origin: .origin, normal: .unitZ)),
                parameterCurve: .constantV(v: 0, uStart: 0, uEnd: 1),
                start: 2, end: 6, reversed: false, tolerance: .standard,
                using: &execution)
        }
        return (source, handle)
    }

    private func queryRange() throws -> ScalarInterval { try .init(lower: 2, upper: 6) }

    private func selectedTotalWork() throws -> Int {
        var execution = try execution()
        let issued = try issue(using: &execution)
        _ = try issued.source.enclosure(over: queryRange(), tolerance: .standard)
        return issued.handle.snapshot.work
    }

    private func isWorkRefusal(_ error: any Error) -> Bool {
        if let failure = error as? OriginalQueryFailure {
            return (failure.kernelFailure.code == .resourceLimitExceeded
                && failure.context.resource?.axis == .work) || isWorkRefusal(failure.originalError)
        }
        if let scalar = error as? ExactScalarFailure {
            switch scalar {
            case .resourceLimit(.work): return true
            case .admissionRejected(let original): return isWorkRefusal(original)
            default: return false
            }
        }
        return false
    }

    @Test func ordinaryReadsRetainTheIssuingHandleAfterExecutionLifetimeEnds() throws {
        let issued: (source: ExchangeHostedCurveConversionSource, handle: OriginalQueryContributionHandle) = try {
            var execution = try execution()
            let issued = try issue(using: &execution)
            let activeCount = execution.activeContributionCount
            #expect(activeCount == 0)
            return issued
        }()
        let beforeValidation = issued.handle.snapshot.work
        try issued.source.validate(over: queryRange(), tolerance: .standard)
        let afterValidation = issued.handle.snapshot.work
        #expect(afterValidation > beforeValidation)
        let value = try issued.source.enclosure(over: queryRange(), tolerance: .standard)
        let afterEnclosure = issued.handle.snapshot.work
        #expect(afterEnclosure > afterValidation)
        #expect(value.position.x.lower <= 0 && value.position.x.upper >= 0)
        #expect(value.position.y.lower <= 0 && value.position.y.upper >= 0)
        #expect(value.position.z.lower <= 0 && value.position.z.upper >= 0)
        let singleton = try issued.source.enclosure(over: ScalarInterval(lower: 2, upper: 2), tolerance: .standard)
        let station = try issued.source.pointAndDerivative(at: 2, tolerance: .standard)
        // The source certifies the authored endpoint; the Double station is an enclosed proposal.
        #expect(singleton.position.x.lower <= 0 && singleton.position.x.upper >= 0)
        #expect(singleton.position.y.lower <= 0 && singleton.position.y.upper >= 0)
        #expect(singleton.position.z.lower <= 0 && singleton.position.z.upper >= 0)
        #expect(singleton.position.x.lower <= station.point.x && station.point.x <= singleton.position.x.upper)
        #expect(singleton.position.y.lower <= station.point.y && station.point.y <= singleton.position.y.upper)
        #expect(singleton.position.z.lower <= station.point.z && station.point.z <= singleton.position.z.upper)
        #expect(station.derivative.isFinite)
        #expect(issued.handle.snapshot.work > afterEnclosure)
    }

    @Test func directReadsReattachTheSelectedHandleAroundTheirActualBody() throws {
        var execution = try execution()
        let issued = try issue(using: &execution)
        let countBefore = execution.activeContributionCount
        let before = issued.handle.snapshot.work
        try issued.source.validate(over: queryRange(), tolerance: .standard, using: &execution)
        let afterValidation = issued.handle.snapshot.work
        #expect(afterValidation > before)
        _ = try issued.source.enclosure(over: queryRange(), tolerance: .standard, using: &execution)
        let afterEnclosure = issued.handle.snapshot.work
        #expect(afterEnclosure > afterValidation)
        _ = try issued.source.pointAndDerivative(at: 2, tolerance: .standard, using: &execution)
        #expect(issued.handle.snapshot.work > afterEnclosure)
        let countAfter = execution.activeContributionCount
        #expect(countBefore == 0 && countAfter == 0)
    }

    @Test func exactSelectedWorkBoundaryIncludesPreparationAndRetainedEnclosure() throws {
        let n = try selectedTotalWork()
        #expect(n > 0)
        var exactExecution = try execution()
        let exact = try issue(workLimit: n, using: &exactExecution)
        _ = try exact.source.enclosure(over: queryRange(), tolerance: .standard)
        #expect(exact.handle.snapshot.work == n)

        var insufficientExecution = try execution()
        var returned = false
        do {
            let insufficient = try issue(workLimit: n - 1, using: &insufficientExecution)
            _ = try insufficient.source.enclosure(over: queryRange(), tolerance: .standard)
            returned = true
            Issue.record("N-1 selected work must not publish a hosted enclosure.")
        } catch {
            #expect(isWorkRefusal(error))
        }
        #expect(!returned)
    }

    @Test func foreignBudgetIsStillRejectedBeforeAnyQueryWork() throws {
        var originalExecution = try execution()
        let issued = try issue(using: &originalExecution)
        var foreign = try execution()
        let budget = foreign.budget
        let before = budget.snapshot
        let selectedBefore = issued.handle.snapshot.work
        do {
            _ = try issued.source.enclosure(over: queryRange(), tolerance: .standard, using: &foreign)
            Issue.record("A foreign owner must not read a hosted original chart.")
        } catch GeometryConversionError.invalidInput { }
        catch { Issue.record("Hosted owner check returned an unexpected typed failure: \(error)") }
        #expect(budget.snapshot.work == before.work)
        #expect(budget.snapshot.storageBytes == before.storageBytes)
        #expect(issued.handle.snapshot.work == selectedBefore)
    }
}

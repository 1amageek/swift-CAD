import CADCore
import CADGeometry
import Testing
@testable import CADKernel

@Suite("Prepared Boolean contribution binding", .timeLimit(.minutes(1)))
struct PreparedBooleanContributionBindingTests {
    private func prepared() throws -> (PreparedBooleanQueryLifetime, OriginalQueryContributionHandle) {
        var execution = OriginalQueryExecution(budget: try OriginalQueryBudget(),
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 1, maximumSubdivisionDepth: 8))
        let handle = try execution.makeContributionHandle(workLimit: 1_000,
            storageByteLimit: 1_000_000)
        let lifetime = try execution.withContributionScope(handle) { execution in
            let preparation = try execution.withPreparationScope { execution in
                try execution.admitSourceDepth(1)
                try execution.admitDepth(value: 2, coefficient: 3)
            }
            return try PreparedBooleanQueryLifetime.retain(depth: preparation.depth, using: &execution)
        }
        return (lifetime, handle)
    }

    @Test func actualReaderBodyRetainsTheContributionAfterScopeExit() throws {
        let (lifetime, handle) = try prepared()
        var reader = OriginalQueryExecution(budget: handle.budget, limits: lifetime.limits)
        let before = handle.snapshot.work
        try lifetime.withRead(using: &reader) { execution in
            #expect(execution.activeContributionHandle?.budget === handle.budget)
            try execution.consumeWork(7)
        }
        #expect(handle.snapshot.work >= before + 7)
    }

    @Test func sourceRefusalPrecedesSameBudgetReattachmentStorage() throws {
        let (lifetime, handle) = try prepared()
        var reader = OriginalQueryExecution(budget: handle.budget,
            limits: try .init(maximumValueDepth: 32, maximumCoefficientDepth: 32,
                remainingSourceDepth: 0, maximumSubdivisionDepth: 8))
        let before = handle.budget.snapshot.storageBytes
        do {
            try lifetime.withRead(using: &reader) { _ in
                Issue.record("Source-zero reader entered the retained body.")
            }
            Issue.record("Source-zero reader returned success.")
        } catch {
            let published = OriginalQueryFailure.published(error,
                context: reader.context, tolerance: .standard)
            #expect(OriginalQueryFailure.classification(of: published)?.code == .resourceLimitExceeded)
        }
        #expect(reader.localStorageBytes == 0)
        #expect(handle.budget.snapshot.storageBytes == before)
    }

    @Test func actualBodyCannotEscapeSelectedWorkOrStorageCeilings() throws {
        for storage in [false, true] {
            let (lifetime, handle) = try prepared()
            var reader = OriginalQueryExecution(budget: handle.budget, limits: lifetime.limits)
            do {
                try lifetime.withRead(using: &reader) { execution in
                    if storage { try execution.retainStorage(bytes: 1_000_001) }
                    else { try execution.consumeWork(1_001) }
                }
                Issue.record("Retained reader escaped its selected contribution ceiling.")
            } catch {
                let published = OriginalQueryFailure.published(error,
                    context: reader.context, tolerance: .standard)
                #expect(OriginalQueryFailure.classification(of: published)?.code == .resourceLimitExceeded)
            }
        }
    }
}

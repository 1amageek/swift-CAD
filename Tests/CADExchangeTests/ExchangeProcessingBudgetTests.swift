import Testing
import CADCore
@testable import CADExchange

@Suite("Exchange processing budget")
struct ExchangeProcessingBudgetTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsExpiredDeadlineWithTypedResourceDiagnostic() {
        let budget = ExchangeProcessingBudget(maximumDuration: .zero)

        do {
            try budget.check(format: .step)
            Issue.record("An expired exchange deadline must reject processing.")
        } catch let error as KernelError {
            #expect(error.phase == .exchange)
            #expect(error.code == .resourceLimitExceeded)
        } catch {
            Issue.record("Exchange deadline returned an unexpected error type: \(error)")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func resourceLimitsRequirePositiveProcessingDuration() {
        let limits = ExchangeResourceLimits(maximumProcessingDuration: .zero)

        #expect(throws: KernelError.self) {
            try limits.validate()
        }
    }
}

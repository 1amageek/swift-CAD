@testable import L0
import L0Fixtures
import Testing

@Suite(.timeLimit(.minutes(1)))
struct L0ScalarTests {
    @Test func exactRationalValuesAndOperations() throws { try L0ScalarFixtures.rationals() }
    @Test func originalAlgebraicValuesAndLifetime() throws { try L0ScalarFixtures.algebraic() }
    @Test func failureResourcesAndCancellation() throws { try L0ScalarFixtures.failures() }
    @Test func nativeTaskCancellation() async throws {
        let rejected = try await Task {
            var admission = ExactScalarLedger(limits: try ExactScalarLimits(work: 100, storageBytes: 100, valueDepth: 0, coefficientDepth: 0))
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try ExactRationalScalarDomain().integer(1, using: &admission)
                return false
            } catch ExactScalarFailure.cancelled {
                return admission.work == 0 && admission.storageBytes == 0
            } catch { return false }
        }.value
        #expect(rejected)
    }
    @Test func checkedWordConversionAndInheritedDepth() throws {
        var admission = ExactScalarLedger(limits: try .init(work: 100, storageBytes: 100, valueDepth: 32, coefficientDepth: 32))
        do {
            _ = try ExactScalarNumericAccess.withAdmission(&admission) { numeric in
                try numeric.retainExactStorage(Int.max)
            }
            Issue.record("Word-to-byte overflow published an admitted result")
        } catch ExactScalarFailure.countOverflow {
            #expect(admission.work == 1 && admission.storageBytes == 0)
        }
        do {
            _ = try ExactScalarNumericAccess.withAdmission(&admission,
                original: .init(value: 2, coefficient: 3), inherited: .init(value: 5, coefficient: 7),
                maximum: .init(value: 5, coefficient: 8)) { numeric in
                    try numeric.visitCoefficientCell(depth: 4)
                    try numeric.visitExactCell(depth: 3)
                }
            Issue.record("An inherited depth escaped its explicit operation cap")
        } catch ExactScalarFailure.resourceLimit(.valueDepth) {
            #expect(admission.valueDepth == 5 && admission.coefficientDepth == 8)
        }
    }

    @Test func unmappedFailureRetainsCauseAndSpentWork() throws {
        enum Rejection: Error { case stopped }
        var admission = ExactScalarLedger(limits: try .init(work: 100, storageBytes: 100, valueDepth: 0, coefficientDepth: 0))
        do {
            _ = try ExactScalarNumericAccess.withAdmission(&admission) { numeric in
                try numeric.consumeExactWork(3)
                throw Rejection.stopped
            }
            Issue.record("A rejected invocation published a value")
        } catch ExactScalarFailure.admissionRejected(let cause) {
            #expect(cause is Rejection)
            #expect(admission.work == 4 && admission.storageBytes == 0)
        }
    }

}

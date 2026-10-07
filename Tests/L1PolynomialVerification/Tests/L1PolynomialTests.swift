import L0
import L1
import L1Fixtures
import Testing

@Suite(.timeLimit(.minutes(1)))
struct L1PolynomialTests {
    @Test func rationalAlgebra() throws { try L1AlgebraFixtures.rational() }
    @Test func algebraicAlgebra() throws { try L1AlgebraFixtures.algebraic() }
    @Test func algebraFailures() throws { try L1AlgebraFixtures.failures() }
    @Test func taskCancellation() async throws {
        let result = try await Task {
            var a = ExactScalarLedger(limits: try .init(work: 1000, storageBytes: 1000, valueDepth: 0, coefficientDepth: 0))
            let d = try ExactPolynomialDomain(field: ExactRationalScalarDomain(), variableCount: 1, using: &a)
            let paid = a.work
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try d.zero(using: &a)
                return false
            } catch ExactPolynomialFailure.scalar(.cancelled) { return a.work == paid }
            catch { return false }
        }.value
        #expect(result)
    }
    @Test func primitiveRational() throws { try L1PrimitiveFixtures.rational() }
    @Test func primitiveAlgebraicAndLifetime() throws { try L1PrimitiveFixtures.algebraic() }
    @Test func primitiveFailuresAndResources() throws { try L1PrimitiveFixtures.failures() }
}

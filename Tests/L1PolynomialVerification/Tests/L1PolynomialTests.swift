import L0
import L1
import L1Fixtures
import Testing

@Suite(.timeLimit(.minutes(1)))
struct L1PolynomialTests {
    @Test func primitiveRational() throws { try L1PrimitiveFixtures.rational() }
    @Test func primitiveAlgebraicAndLifetime() throws { try L1PrimitiveFixtures.algebraic() }
    @Test func primitiveFailuresAndResources() throws { try L1PrimitiveFixtures.failures() }
}

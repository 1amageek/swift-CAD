import L1Fixtures
import L0Fixtures

@main
struct L1Proof {
    static func main() throws {
        try L0ScalarFixtures.runAll()
        try L1PrimitiveFixtures.rational()
        try L1PrimitiveFixtures.algebraic()
        try L1PrimitiveFixtures.failures()
        try L1AlgebraFixtures.rational()
        try L1AlgebraFixtures.algebraic()
        try L1AlgebraFixtures.failures()
        try L1ZeroProductFixtures.run()
        print("PASS: L1 zero-product owner, depth, resources and cancellation")
        print("PASS: L1 division, multivariate GCD, square-free decomposition and resultant")
        print("PASS: L1 primitives, retained coefficients, lifetime and resource failures")
    }
}

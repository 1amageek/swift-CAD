import L1Fixtures

@main
struct L1Proof {
    static func main() throws {
        try L1PrimitiveFixtures.rational()
        try L1PrimitiveFixtures.algebraic()
        try L1PrimitiveFixtures.failures()
        print("PASS: L1 primitives, retained coefficients, lifetime and resource failures")
    }
}

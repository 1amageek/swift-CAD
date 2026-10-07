import L0Fixtures

@main
struct L0Proof {
    static func main() throws {
        try L0ScalarFixtures.runAll()
        print("PASS: L0 exact values, decisions, arithmetic, lifetime, resources and cancellation")
    }
}

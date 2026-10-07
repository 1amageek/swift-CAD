import L2Fixtures
@main struct L2Proof {
    static func main() throws {
        try RootFixtures.rational()
        try RootFixtures.domains()
        try RootFixtures.exactQueries()
        try RootFixtures.failures()
        print("PASS: complete roots, multiplicity, exact order, signs and refinement")
    }
}

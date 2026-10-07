import L2Fixtures
@main struct L2Proof {
    static func main() throws {
        try RootFixtures.rational()
        try RootFixtures.domains()
        try RootFixtures.exactQueries()
        try RootFixtures.failures()
        try FieldFixtures.tower()
        try FieldFixtures.reducible()
        try FieldFixtures.failures()
        try EdgeFixtures.finalCancellationAndStorage()
        try EdgeFixtures.retainedOwnersAndSelectedVariable()
        try EdgeFixtures.generalDegreeAndOddMultiplicity()
        try OriginalBaseFixtures.run()
        print("PASS: complete roots, multiplicity, exact order, signs and refinement")
    }
}

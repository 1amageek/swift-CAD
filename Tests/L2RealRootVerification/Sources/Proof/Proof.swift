import L2Fixtures
@main struct L2Proof {
    static func main() throws {
        try SignedDecisionFixtures.verify()
        try LocalLawFixtures.verify()
        try TransportFixtures.verify()
        try CountReuseFixtures.verify()
  try CountReuseFixtures.factored()
        try SeparationFixtures.verify()
        try RootFixtures.definingDivisorRefinement()
        try RootFixtures.exactCandidateCompletion()
        try RootFixtures.rational()
        try RootFixtures.domains()
        try RootFixtures.exactQueries()
        try RootFixtures.failures()
        try CellVisitFixtures.run()
        try CanonicalScalarFixtures.verify()
        try FieldFixtures.tower()
        try FieldFixtures.denominatorUnits()
        try FieldFixtures.reducible()
        try FieldFixtures.failures()
        try EdgeFixtures.finalCancellationAndStorage()
        try EdgeFixtures.retainedOwnersAndSelectedVariable()
        try EdgeFixtures.generalDegreeAndOddMultiplicity()
        try OriginalBaseFixtures.run()
        print("PASS: complete roots, multiplicity, exact order, signs and refinement")
    }
}

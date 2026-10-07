import Testing
import L2Fixtures
@Test(.timeLimit(.minutes(1))) func rationalRoots() throws { try RootFixtures.rational() }
@Test(.timeLimit(.minutes(1))) func rootDomains() throws { try RootFixtures.domains() }
@Test(.timeLimit(.minutes(1))) func exactQueries() throws { try RootFixtures.exactQueries() }
@Test(.timeLimit(.minutes(1))) func rootFailures() throws { try RootFixtures.failures() }
@Test(.timeLimit(.minutes(1))) func algebraicTower() throws { try FieldFixtures.tower() }
@Test(.timeLimit(.minutes(1))) func reducibleLaw() throws { try FieldFixtures.reducible() }
@Test(.timeLimit(.minutes(1))) func fieldFailures() throws { try FieldFixtures.failures() }
@Test(.timeLimit(.minutes(1))) func finalCancellationAndStorage() throws { try EdgeFixtures.finalCancellationAndStorage() }
@Test(.timeLimit(.minutes(1))) func retainedOwners() throws { try EdgeFixtures.retainedOwnersAndSelectedVariable() }
@Test(.timeLimit(.minutes(1))) func generalDegree() throws { try EdgeFixtures.generalDegreeAndOddMultiplicity() }
@Test(.timeLimit(.minutes(1))) func existingAlgebraicBase() throws { try OriginalBaseFixtures.run() }

import Testing
import L2Fixtures
@Test(.timeLimit(.minutes(1))) func rationalRoots() throws { try RootFixtures.rational() }
@Test(.timeLimit(.minutes(1))) func rootDomains() throws { try RootFixtures.domains() }
@Test(.timeLimit(.minutes(1))) func exactQueries() throws { try RootFixtures.exactQueries() }
@Test(.timeLimit(.minutes(1))) func rootFailures() throws { try RootFixtures.failures() }

import Testing
import SourceIssuerFixtures

@Test(.timeLimit(.minutes(1))) func originalExactLaws() throws { try SourceFixtures.exactLaws() }
@Test(.timeLimit(.minutes(1))) func originalSelectedSpansAndTensor() throws { try SourceFixtures.selectedSpansAndTensor() }
@Test(.timeLimit(.minutes(1))) func originalOwnership() throws { try SourceFixtures.ownership() }
@Test(.timeLimit(.minutes(1))) func originalTypedFailures() throws { try SourceFixtures.failures() }
@Test(.timeLimit(.minutes(1))) func originalCumulativeResources() throws { try SourceFixtures.resources() }

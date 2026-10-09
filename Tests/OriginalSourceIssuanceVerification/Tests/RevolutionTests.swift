import Testing
import SourceIssuerFixtures

@Test(.timeLimit(.minutes(1))) func originalRevolutionSupply() throws { try SourceFixtures.revolutionLaws() }

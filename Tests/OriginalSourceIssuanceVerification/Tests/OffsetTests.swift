import Testing
import SourceIssuerFixtures

@Test(.timeLimit(.minutes(1))) func originalGuardedOffsetSupply() throws { try SourceFixtures.offsetLaws() }

import Testing
import SourceIssuerFixtures

@Test(.timeLimit(.minutes(1))) func originalRetainedSurfaceSupply() throws { try SourceFixtures.retainedSurfaceLaws() }

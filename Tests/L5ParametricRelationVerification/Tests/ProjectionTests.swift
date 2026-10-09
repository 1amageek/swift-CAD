import Testing
import L4ProjectionFixtures

@Test(.timeLimit(.minutes(1))) func exactAuxiliaryProjection() throws { try ProjectionFixtures.geometryIndependentProjection() }
@Test(.timeLimit(.minutes(1))) func exactProjectionFailures() throws { try ProjectionFixtures.failures() }

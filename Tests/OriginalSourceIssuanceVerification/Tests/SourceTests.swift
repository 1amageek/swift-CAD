import Testing
import SourceIssuerFixtures

@Test(.timeLimit(.minutes(1))) func originalExactLaws() throws { try SourceFixtures.exactLaws() }
@Test(.timeLimit(.minutes(1))) func originalSelectedSpansAndTensor() throws { try SourceFixtures.selectedSpansAndTensor() }
@Test(.timeLimit(.minutes(1))) func originalPeriodicLaws() throws { try SourceFixtures.periodicLaws() }
@Test(.timeLimit(.minutes(1))) func originalImplicitImages() throws { try SourceFixtures.implicitImages() }
@Test(.timeLimit(.minutes(1))) func originalOwnership() throws { try SourceFixtures.ownership() }
@Test(.timeLimit(.minutes(1))) func originalTypedFailures() throws { try SourceFixtures.failures() }
@Test(.timeLimit(.minutes(1))) func originalCumulativeResources() throws { try SourceFixtures.resources() }

@Test(.timeLimit(.minutes(1))) func physicalAngleCoefficients() throws { try SourceFixtures.physicalAngleCoefficients() }
@Test(.timeLimit(.minutes(1))) func physicalAngleResources() throws { try SourceFixtures.physicalAngleResources() }

@Test(.timeLimit(.minutes(1))) func coneImages() throws { try SourceFixtures.coneImages() }

@Test(.timeLimit(.minutes(1))) func heterogeneousRuledLaws() throws { try SourceFixtures.ruledLaws() }

@Test(.timeLimit(.minutes(1))) func spatialLaws() throws { try SourceFixtures.spatialLaws() }

@Test(.timeLimit(.minutes(1))) func parameterImageLaws() throws { try SourceFixtures.parameterImageLaws() }

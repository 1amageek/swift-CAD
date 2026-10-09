import Testing
import DomainFixtures
@Test(.timeLimit(.minutes(1))) func allEndpointSectors() throws { try DomainFixtures.endpointAlgebra() }
@Test(.timeLimit(.minutes(1))) func canonicalDisconnectedUnboundedSets() throws { try DomainFixtures.canonicalAndDisconnected() }
@Test(.timeLimit(.minutes(1))) func productsAndRetainedOwners() throws { try DomainFixtures.productsAndLifetime() }
@Test(.timeLimit(.minutes(1))) func explicitFailuresAndAdmission() throws { try DomainFixtures.rejectionAndBudgets() }

@Test(.timeLimit(.minutes(1))) func immutableReadersAndTaskCancellation() async throws { try await DomainFixtures.concurrentReadersAndTaskCancel() }

@Test(.timeLimit(.minutes(1))) func sourceAffineCorrespondence() throws { try TransportFixtures.affineAndComposition() }
@Test(.timeLimit(.minutes(1))) func exactPeriodicLiftsAndRefusal() throws { try TransportFixtures.periodsAndRefusal() }

@Test(.timeLimit(.minutes(1))) func completeFiniteCoversAndHoles() throws { try CoverageFixtures.finiteAndHoles() }
@Test(.timeLimit(.minutes(1))) func completeIntegerFamiliesAndTensorOwners() throws { try CoverageFixtures.periodicAndTensor() }

@Test(.timeLimit(.minutes(1))) func scopedIdentityAndExactPeriodOrbits() throws { try IdentityFixtures.scopedCoordinatesAndPeriods() }
@Test(.timeLimit(.minutes(1))) func sourceCollapsedSubsetsAndOneSidedBoundaries() throws { try IdentityFixtures.collapsedAndBoundaryLaws() }
@Test(.timeLimit(.minutes(1))) func verifyEntireDeclaredBoundary() throws { try IdentityFixtures.declaredWholeBoundary() }

@Test(.timeLimit(.minutes(1))) func intrinsicPolesAndPhysicalMeaningRefusal() throws { try IntrinsicFixtures.polesAndMeaning() }
@Test(.timeLimit(.minutes(1))) func completeSourceDomainChartHandoff() throws { try IntrinsicFixtures.sourceDomainHandoff() }

@Test(.timeLimit(.minutes(1))) func originalStoredNormalPlaneBasisAndUV() throws { try PlaneFixtures.exactBasisAndUV() }

@Test(.timeLimit(.minutes(1))) func scaledStoredNormalsAndExactPlaneUV() throws { try PlaneFixtures.scaledNormalsAndUV() }

@Test(.timeLimit(.minutes(1))) func rationalSharedDivisorPreservesCostAndFailures() throws { try RepeatedDivisionFixtures.rational() }
@Test(.timeLimit(.minutes(1))) func selectedRootSharedDivisorRetainsLocalInverseLaws() throws { try RepeatedDivisionFixtures.localInverse() }

@Test(.timeLimit(.minutes(1))) func chartFamilyWitnessesAndInjection() throws { try FamilyQueryFixtures.witnessesAndInjection() }

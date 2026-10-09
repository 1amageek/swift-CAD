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

@Test(.timeLimit(.minutes(1))) func finiteOriginalChartSelections() throws { try FiniteFamilyQueryFixtures.completeSelection() }
@Test(.timeLimit(.minutes(1))) func mathematicalPiDomain() throws { try PiDomainFixtures.exactPiAndFailures() }
@Test(.timeLimit(.minutes(1))) func wholeOriginalLineAndPlaneDomains() throws { try PrimitiveDomainFixtures.wholeLineAndPlane() }
@Test(.timeLimit(.minutes(1))) func wholeOriginalAnalyticDomains() throws { try AnalyticDomainFixtures.intrinsicWholeDomains() }

@Test(.timeLimit(.minutes(1))) func originalPhysicalAngularDomains() throws { try AnalyticDomainFixtures.physicalPhasePeriodsAndPoles() }

@Test(.timeLimit(.minutes(1))) func composedSourceFamilies() throws { try ComposedDomainFixtures.completeFamilies() }
@Test(.timeLimit(.minutes(1))) func composedSourcePullbackFailures() throws { try ComposedDomainFixtures.completePullbackAndFailures() }

@Test(.timeLimit(.minutes(1))) func checkedAffineAndIdentityRelationViews() throws { try RelationViewFixtures.affineWordsAndLifetime() }
@Test(.timeLimit(.minutes(1))) func checkedRelationProductAndAdmission() throws { try RelationViewFixtures.completeProductsAndFailures() }

@Test(.timeLimit(.minutes(1))) func analyticScopedPeriodsAndFibers() throws { try AnalyticIdentityFixtures.intrinsicPeriodsAndFibers() }
@Test(.timeLimit(.minutes(1))) func analyticPhysicalPeriodClippingAndFailures() throws { try AnalyticIdentityFixtures.physicalClippingAndFailures() }

@Test(.timeLimit(.minutes(1))) func wholeRevolutionDomainFamiliesAndGuards() throws { try RevolutionDomainFixtures.completeFamiliesAndGuards() }
@Test(.timeLimit(.minutes(1))) func wholeRevolutionDomainRefusal() throws { try RevolutionDomainFixtures.admissionAndRefusal() }

@Test(.timeLimit(.minutes(1))) func guardedOffsetCoverageAndOwnership() throws { try OffsetDomainFixtures.guardedCoverageAndOwnership() }
@Test(.timeLimit(.minutes(1))) func guardedOffsetFailures() throws { try OffsetDomainFixtures.guardedFailures() }

@Test(.timeLimit(.minutes(1))) func scopedRevolutionPeriodIdentities() throws { try RevolutionIdentityFixtures.scopedPeriodAndClipping() }
@Test(.timeLimit(.minutes(1))) func scopedRevolutionIdentityFailures() throws { try RevolutionIdentityFixtures.identityFailures() }

@Test func completeGuideSourceDomainCorrespondence() throws { try GuideDomainFixtures.fullSourceCorrespondence() }
@Test func guideDomainAdmissionFailures() throws { try GuideDomainFixtures.admissionAndFailures() }

@Test func retainedSurfaceDomainCorrespondence() throws { try RetainedSurfaceDomainFixtures.fullSourceCorrespondence() }
@Test func retainedSurfaceDomainAdmissionFailures() throws { try RetainedSurfaceDomainFixtures.atomicFailures() }

import Testing
import DomainFixtures
@Test(.timeLimit(.minutes(1))) func allEndpointSectors() throws { try DomainFixtures.endpointAlgebra() }
@Test(.timeLimit(.minutes(1))) func canonicalDisconnectedUnboundedSets() throws { try DomainFixtures.canonicalAndDisconnected() }
@Test(.timeLimit(.minutes(1))) func productsAndRetainedOwners() throws { try DomainFixtures.productsAndLifetime() }
@Test(.timeLimit(.minutes(1))) func explicitFailuresAndAdmission() throws { try DomainFixtures.rejectionAndBudgets() }

@Test(.timeLimit(.minutes(1))) func immutableReadersAndTaskCancellation() async throws { try await DomainFixtures.concurrentReadersAndTaskCancel() }

import Testing
import NativeExactFixtures
@Test(.timeLimit(.minutes(1))) func nativeCS() throws { try NativeExactFixtures.verifyCS() }
@Test(.timeLimit(.minutes(1))) func nativeSSI() throws { try NativeExactFixtures.verifySSI() }
@Test(.timeLimit(.minutes(1))) func nativeFailures() throws { try NativeExactFixtures.verifyFailures() }

@Test(.timeLimit(.minutes(1))) func nativeProvenance() throws { try NativeProvenanceFixtures.verify() }

@Test(.timeLimit(.minutes(1))) func nativePreparation() throws { try NativePreparationFixtures.verify() }

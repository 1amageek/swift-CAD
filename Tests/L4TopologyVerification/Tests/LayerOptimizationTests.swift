import Testing
import L4Fixtures
@Test(.timeLimit(.minutes(1))) func orderedProductOptimization() throws { try LayerOptimizationFixtures.orderedProducts() }
@Test(.timeLimit(.minutes(1))) func singletonSignOptimization() throws { try LayerOptimizationFixtures.singletonSigns() }
@Test(.timeLimit(.minutes(1))) func retainedPairOptimization() throws { try LayerOptimizationFixtures.retainedPairTruth() }

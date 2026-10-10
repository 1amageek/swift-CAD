import Testing
import GraphFixtures

@Test(.serialized, .timeLimit(.minutes(2)), arguments: 0..<3)
func issuedGraphSources(_ mode: Int) throws { try GraphFixtures.run(mode) }

@Test(.serialized, .timeLimit(.minutes(2)), arguments: 3..<8)
func issuedGraphPublication(_ mode: Int) throws { try GraphFixtures.run(mode) }

@Test(.serialized, .timeLimit(.minutes(2)), arguments: 8..<14)
func issuedGraphFibers(_ mode: Int) throws { try GraphFixtures.run(mode) }

@Test(.timeLimit(.minutes(2)))
func issuedGraphParameterRefinement() throws { try GraphFixtures.run(15) }

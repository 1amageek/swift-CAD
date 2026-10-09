import Testing
import L5Fixtures
@Suite struct RelationTests {
    @Test(.timeLimit(.minutes(1))) func cs() throws { try RelationFixtures.csRelations() }
    @Test(.timeLimit(.minutes(1))) func ssi() throws { try RelationFixtures.foldedSSI() }
    @Test(.timeLimit(.minutes(1))) func lifetime() throws { try RelationFixtures.domainsAndLifetime() }
    @Test(.timeLimit(.minutes(1))) func failures() throws { try FailureFixtures.verify() }
}

@Test(.serialized, .timeLimit(.minutes(1)), arguments: 0..<9) func guardedGraphRelations(_ mode: Int) throws { try GraphRelationFixtures.graphRelations(modes: mode..<(mode+1)) }
@Test(.timeLimit(.minutes(1))) func guardedGraphFailures() throws { try GraphRelationFixtures.failuresAndLifetime() }

@Test(.timeLimit(.minutes(1))) func graphInheritedDepth() throws { try GraphDepthFixtures.inheritedDepth() }

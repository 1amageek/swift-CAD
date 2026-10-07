import Testing
import L5Fixtures
@Suite struct RelationTests {
    @Test(.timeLimit(.minutes(1))) func cs() throws { try RelationFixtures.csRelations() }
    @Test(.timeLimit(.minutes(1))) func ssi() throws { try RelationFixtures.foldedSSI() }
    @Test(.timeLimit(.minutes(1))) func lifetime() throws { try RelationFixtures.domainsAndLifetime() }
    @Test(.timeLimit(.minutes(1))) func failures() throws { try FailureFixtures.verify() }
}

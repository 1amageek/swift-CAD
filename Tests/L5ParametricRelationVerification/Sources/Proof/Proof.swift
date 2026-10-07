import L5Fixtures
@main struct L5Proof {
    static func main() throws {
        try RelationFixtures.csRelations()
        try RelationFixtures.foldedSSI()
        try RelationFixtures.domainsAndLifetime()
        try FailureFixtures.verify()
        print("PASS: independent original parameter relation composition")
    }
}

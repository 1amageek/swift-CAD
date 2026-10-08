import Testing
import L2Fixtures
import L0
import L1
import L2
@Test(.timeLimit(.minutes(1))) func rationalRoots() throws { try RootFixtures.rational() }
@Test(.timeLimit(.minutes(1))) func rootDomains() throws { try RootFixtures.domains() }
@Test(.timeLimit(.minutes(1))) func exactQueries() throws { try RootFixtures.exactQueries() }
@Test(.timeLimit(.minutes(1))) func exactCandidateRefinement() throws { try RootFixtures.exactCandidateRefinement() }
@Test(.timeLimit(.minutes(1))) func rootFailures() throws { try RootFixtures.failures() }
@Test(.timeLimit(.minutes(1))) func algebraicTower() throws { try FieldFixtures.tower() }
@Test(.timeLimit(.minutes(1))) func reducibleLaw() throws { try FieldFixtures.reducible() }
@Test(.timeLimit(.minutes(1))) func fieldFailures() throws { try FieldFixtures.failures() }
@Test(.timeLimit(.minutes(1))) func finalCancellationAndStorage() throws { try EdgeFixtures.finalCancellationAndStorage() }
@Test(.timeLimit(.minutes(1))) func retainedOwners() throws { try EdgeFixtures.retainedOwnersAndSelectedVariable() }
@Test(.timeLimit(.minutes(1))) func generalDegree() throws { try EdgeFixtures.generalDegreeAndOddMultiplicity() }
@Test(.timeLimit(.minutes(1))) func existingAlgebraicBase() throws { try OriginalBaseFixtures.run() }

@Test(.timeLimit(.minutes(1))) func concurrentImmutableRootReaders() async throws {
    var preparation: ExactScalarLedger = .init(limits: try ExactScalarLimits(work: 20_000_000, storageBytes: 50_000_000, valueDepth: 100, coefficientDepth: 100))
    let field = ExactRationalScalarDomain()
    let domain = try ExactRealRootDomain(field: field, using: &preparation)
    let p = domain.polynomials, x = try p.variable(0, using: &preparation)
    let source = try domain.bind(p.subtracting(p.multiplying(x, x, using: &preparation),
        p.constant(field.integer(2, using: &preparation), using: &preparation), using: &preparation), using: &preparation)
    let all = try domain.domain(lower: .negativeInfinity, upper: .positiveInfinity, using: &preparation)
    let root = try domain.isolate(source, in: all, limits: .init(maximumRoots: 2), using: &preparation).roots[1]
    try await withThrowingTaskGroup(of: Bool.self) { group in
        for _ in 0..<4 {
            group.addTask {
                var admission: ExactScalarLedger = .init(limits: try ExactScalarLimits(work: 20_000_000, storageBytes: 50_000_000, valueDepth: 100, coefficientDepth: 100))
                return try domain.sign(of: source, at: root, using: &admission) == .zero
            }
        }
        for try await result in group { try RootFixtures.require(result) }
    }
}

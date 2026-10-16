import Testing

@Suite("Original query diagnostic prefixes", .timeLimit(.minutes(1)))
struct OriginalQueryDiagnosticPrefixTests {
    @Test
    func prefixPreservesEveryPublishedFieldAndInnerContext() throws {
        try OriginalQueryDiagnosticPrefixChecks.prefixPreservesEveryPublishedFieldAndInnerContext()
    }

    @Test
    func rawResourcePublicationRetainsCauseAndFillsOnlyMissingContext() throws {
        try OriginalQueryDiagnosticPrefixChecks.rawResourcePublicationRetainsCauseAndFillsOnlyMissingContext()
    }

    @Test
    func explicitClassificationOwnerStillControlsItsAggregateDecision() throws {
        try OriginalQueryDiagnosticPrefixChecks.explicitClassificationOwnerStillControlsItsAggregateDecision()
    }

    @Test
    func diagnosticPrefixNeverClassifiesCancellationOrInventsForeignAuthority() throws {
        try OriginalQueryDiagnosticPrefixChecks.diagnosticPrefixNeverClassifiesCancellationOrInventsForeignAuthority()
    }

}

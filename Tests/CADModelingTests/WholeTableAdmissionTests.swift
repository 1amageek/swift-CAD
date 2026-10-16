import Testing

@Suite("Whole parameter table caller admission", .timeLimit(.minutes(1)))
struct WholeTableAdmissionTests {
    @Test func completeRootsRetainOriginalUnitsAndValues() throws {
        try WholeTableAdmissionChecks.completeRootsRetainOriginalUnitsAndValues()
    }
    @Test func originalRejectionsKeepTheirOrderAndCause() throws {
        try WholeTableAdmissionChecks.originalRejectionsKeepTheirOrderAndCause()
    }
    @Test func exactWorkAndTypedStorageCeilings() throws {
        try WholeTableAdmissionChecks.exactWorkAndTypedStorageCeilings()
    }
    @Test func independentSourceAndValueDepths() throws {
        try WholeTableAdmissionChecks.independentSourceAndValueDepths()
    }
    @Test func selectedContributionsAndPrefixRemainCumulative() throws {
        try WholeTableAdmissionChecks.selectedContributionsAndPrefixRemainCumulative()
    }
    @Test func entryInteriorAndFinalCancellationPublishNothing() throws {
        try WholeTableAdmissionChecks.entryInteriorAndFinalCancellationPublishNothing()
    }
    @Test func outputSurvivesSourceAndCallerRelease() throws {
        try WholeTableAdmissionChecks.outputSurvivesSourceAndCallerRelease()
    }
    @Test func legacyProviderExplicitlyRefusesDirectCapability() throws {
        try WholeTableAdmissionChecks.legacyProviderExplicitlyRefusesDirectCapability()
    }
}

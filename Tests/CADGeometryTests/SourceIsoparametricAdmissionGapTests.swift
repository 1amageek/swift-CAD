import Testing

@Suite("Source isoparametric admission gaps")
struct SourceIsoparametricAdmissionGapTests {
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func selectedMiddleCurveJetsUseTheCallerStorageAdmission(restricted: Bool) throws {
        try SourceDirectAdmissionChecks.Graph.selectedMiddleCurveJetsUseTheCallerStorageAdmission(restricted: restricted)
    }
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func originalGraphLawsRetainDirectionsAndExactCallerLimits(restricted: Bool) throws {
        try SourceDirectAdmissionChecks.Graph.originalGraphLawsRetainDirectionsAndExactCallerLimits(restricted: restricted)
    }
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func graphReadersPreserveCallerCancellation(restricted: Bool) throws {
        try SourceDirectAdmissionChecks.Graph.graphReadersPreserveCallerCancellation(restricted: restricted)
    }
}

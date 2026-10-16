import Testing

@Suite("Source direct admission gaps")
struct SourceDirectAdmissionGapTests {
    @Test(.timeLimit(.minutes(1)))
    func stationaryNativeSupportCannotResetCallerSourceDepth() throws {
        try SourceDirectAdmissionChecks.stationaryNativeSupportCannotResetCallerSourceDepth()
    }
    @Test(.timeLimit(.minutes(1)))
    func originalGainAdmitsItsActualFactorPayloadBeforeRetention() throws {
        try SourceDirectAdmissionChecks.originalGainAdmitsItsActualFactorPayloadBeforeRetention()
    }
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func sourceOperationsPreserveExactCallerResourceBoundaries(native: Bool) throws {
        try SourceDirectAdmissionChecks.sourceOperationsPreserveExactCallerResourceBoundaries(native: native)
    }
    @Test(.timeLimit(.minutes(1)), arguments: [false, true])
    func sourceOperationsObserveEntryAndTerminalCancellation(native: Bool) throws {
        try SourceDirectAdmissionChecks.sourceOperationsObserveEntryAndTerminalCancellation(native: native)
    }
    @Test(.timeLimit(.minutes(1)))
    func factorOwnersAndIndependentZeroDepthKeepTheOriginalImageLaw() throws {
        try SourceDirectAdmissionChecks.factorOwnersAndIndependentZeroDepthKeepTheOriginalImageLaw()
    }
}

import Testing

@Suite("Kernel UV splitter diagnostics", .timeLimit(.minutes(1)))
struct KernelUVSplitDiagnosticTests {
    @Test func emptyGraphRemainsAGenuineEmptySplit() throws {
        try KernelUVSplitDiagnosticChecks.emptyGraphRemainsAGenuineEmptySplit()
    }
    @Test func lowerWorkRefusalRetainsItsOriginalClassification() throws {
        try KernelUVSplitDiagnosticChecks.lowerWorkRefusalRetainsItsOriginalClassification()
    }
    @Test func lowerCallerCancellationRetainsItsOriginalCause() throws {
        try KernelUVSplitDiagnosticChecks.lowerCallerCancellationRetainsItsOriginalCause()
    }
    @Test func externalProviderRetainsItsEmptyCapabilityFallbackAndCaller() throws {
        try KernelUVSplitDiagnosticChecks.externalProviderRetainsItsEmptyCapabilityFallbackAndCaller()
    }
    @Test func exactPlanarCutRetainsItsSourceAndUVLaw() throws {
        try KernelUVSplitDiagnosticChecks.exactPlanarCutRetainsItsSourceAndUVLaw()
    }
}

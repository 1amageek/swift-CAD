@main
struct KernelUVSplitDiagnosticPortable {
    static func main() throws {
        try KernelUVSplitDiagnosticChecks.emptyGraphRemainsAGenuineEmptySplit()
        print("PASS emptyGraphRemainsAGenuineEmptySplit")
        try KernelUVSplitDiagnosticChecks.lowerWorkRefusalRetainsItsOriginalClassification()
        print("PASS lowerWorkRefusalRetainsItsOriginalClassification")
        try KernelUVSplitDiagnosticChecks.lowerCallerCancellationRetainsItsOriginalCause()
        print("PASS lowerCallerCancellationRetainsItsOriginalCause")
        try KernelUVSplitDiagnosticChecks.externalProviderRetainsItsEmptyCapabilityFallbackAndCaller()
        print("PASS externalProviderRetainsItsEmptyCapabilityFallbackAndCaller")
        try KernelUVSplitDiagnosticChecks.exactPlanarCutRetainsItsSourceAndUVLaw()
        print("PASS exactPlanarCutRetainsItsSourceAndUVLaw")
    }
}
